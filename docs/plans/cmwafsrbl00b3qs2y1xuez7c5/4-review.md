# t12 plan review

## Round 1

VERDICT: CHANGES_REQUESTED

The placement, the static arithmetic and the overall test shape are right. I re-derived every figure from the code and they hold:
- Worst life: the free test is `carrier.gd:95`. The world rect is −444..1164 (`arena_camera.gd:88`, `_visible_rect()`), and the hull is 176 × 280 (`carrier.tscn:37`), so the carrier is freed once its centre passes y 1304.
- Highest spawn: `wave_manager.gd:194` puts it at y 360 − 380 − 8 − 520 = −548. (1304 + 548) / 90 + 2/60 = 20.61 s.
- Lit windows: `lit_seconds()` is 8.4 s (`level1_slice_replay.gd:191`). The 55.0 s set ends at 63.4 s, before the spawn. The 98.0 s set starts after 85.61 s.
- Swept x: world anchoring is at `carrier.gd:76`. The sway is clamped to ±30 at `carrier_brain.gd:477`. The widest part is a hangar edge at 60 + 32 = 92 px, which is ≤ `module_x_extent` 100. That gives 620–880, which clears the 550 and 950 columns by 70 px against the 56 px needed.
- Columns: they are world-fixed (`level_1_director.gd:245`). The beam is 1536 px long from y −380, so it reaches the carrier at y 810–1156.
- The rejected stub position: the replay stub sits at the usual place (its own camera offset +220), so the carrier would be gone before the 78.0 s set turns lethal at 81.56 s. That justifies the deviation.
- Other replays: no replay other than the ph9 jammer slice holds the 65.0 s wave. test_mine_layer's window ends at 47 + 9 + 7 = 63 s. The sniper and ram budget rows and the fighter fire-density row filter by scene. `test_level_1_sequence.gd` has no camera, so `wave_manager.gd:180` spawns nothing there.
- ph9 jammer slice: the carrier first comes within 340 px of the stub at about 67.6 s, after the lock at about 65.9 s.
- Gate time: the measured t11 cost (`test_level1_heavy_spawns.gd` 4.6 s for about 50 lit and unlit game seconds) puts a 22 s lit replay at about 2 s. That is tight, but the plan names it as a risk.

Four findings need changes (1–4). Findings 5–7 are small.

1. **The drone-interval model is not conservative for how `CarrierHangars` really launches.** Plan §2 sets `launch_windows().earliest` to spawn + `first_launch_delay` (+ `starboard_launch_delay`) + `door_open_seconds`. It then claims "whatever the camera does, every drone is alive only inside it". That claim is false.
   - `carrier_brain.gd:432-449`: on PANIC entry, `_on_panic_entered()` calls `CarrierHangars.emergency_deploy()`.
   - `carrier_hangars.gd:118-129`: `emergency_deploy()` calls `_launch()` on every bay that has not launched yet (`_may_launch()` in Assault is `launches == 0`). It does not check the schedule clock, `active`, or view entry.
   - PANIC needs only 3 outer wrecks. Before the hangars open, the guns (160 HP) and engines (180 HP) are hittable (`carrier.tscn:164-242`), about 520 HP in total. A player can do that in a few seconds.
   - So a starboard pair can come out several seconds before its computed `earliest` (and a port pair before spawn + 3.8 s), even before the hull enters the view.

   **Required:** for the drone gate, use spawn as each interval's start. This is the honest bound, and C3 still computes ≤ 10 of 12 capable and ≤ 13 of 15 all. Keep the tight per-bay windows only for the attack-in-budget row's "launch inside its window" assertion. That replay damages no part, so no PANIC happens there; say so in the row's comment.

   I checked one more possible gap: the 4th drone is marked REAR, but roles rotate once the port pair dies. That is moot today, because `rear_engage_seconds` equals `engage_seconds` (5.5) in `swarm_drone_config.tres:27,36`.

2. **The lit replay can fail only on an actual kill. Add the margin assertions t11 already has.**
   - t11's row asserts `clearance.lethal >= LaserRay._HAZARD_PAD` (`test_level1_heavy_spawns.gd:776`). Plan §3 asserts only that the clearance is finite and prints it.
   - Without a floor, a regression that eats into the margin but does not yet kill passes green. Examples: a broken sway leash, a lost world anchoring, or a module moved outward.
   - The replay measures against the hull's root `HurtBox` (`level1_slice_replay.gd:484`, ±88). The static model predicts a gap of at least 200 − 30 − 88 − 28 = 54 px to a lethal 550 / 950 strip.

   **Required:**
   - Assert `clearance.lethal >=` that floor, computed from `module_x_extent`, `assault_sway_leash`, `_BEAM_WIDTH` and the hull half-width read from the scene. At a minimum, assert `>= LaserRay._HAZARD_PAD`, as t11 does.
   - Record the carrier's largest `|global_position.x − brain.anchor_x()|` each tick and assert it is `<= assault_sway_leash` (plus an epsilon). This checks the one runtime input of the swept-x model directly in the replay.

3. **The gate-time lever removes an assertion.** Risks says the lever is to "stop at the carrier's departure and drop the sanity row's 'after the window' read". That drops the `lethal_at_stop == 0` / last-tick-after-the-window check. Both §2.15 and the README forbid saving time by "removing an assertion".
   - The cost is small anyway: about 0.8 game s (85.6 → 86.43 s), roughly 0.07 s of wall time at 16×.

   **Required:** remove this lever. If the replay is over budget, the stated rules apply: memoise and share the run, or escalate.

4. **The context's "usual stub" arithmetic is wrong. Fix it before it goes into DECISIONS.**
   - `PLAYER_OFFSET` (0, 250) minus the 30 px deadzone gives a camera offset of +220 (`arena_camera.gd:132-146`).
   - The spawn y is then 360 + 220 − 520 = 60. The carrier is freed at (1304 − 60) / 90 = 13.8 s, about **78.8 s**.
   - That is about 600 px lower than the worst case, not "~250 px", and earlier than "~81 s" (plan §3 and `1-context.md`, the arena_camera / slice_replay rows).
   - The conclusion (vacuous at the usual place) holds, and even more strongly.
   - The opt-in offset `−(V_LIMIT + deadzone.y + 50)` is correct: stub y −100, a target of −430 clamped to −380, and the lerp converges well inside `PRE_ROLL`.

5. **The drone-gate boundary uses a typed offset (minor).** "Two more carriers inserted 5 s before the all-drones peak" is a typed number. With the current windows only the port pairs would cover the peak instant, so whether it trips depends on where the peak moves.
   - Derive the insertion time from the config so that both bays' intervals contain the peak. With finding 1 applied, any time in [peak − worst life, peak] works.
   - Assert that the boundary's all-drones peak is greater than `_C3_ALL_RATIO` × legacy.

6. **The spill row's drone lifetime has no single source (minor).** The heavy-spawns spill row needs "max drone lifetime". Today that lives only in `test_level1_drone_spawns.gd::_c3_lifetimes()` (`:363`), as a test method.
   - Move the computation into `level1_carrier_timeline.gd` (or `DroneConcurrency`) so both files read one formula: `engage_seconds` + `worst_exit_seconds(...)`, about 8.1 s today, which gives children gone by about 93.7 s against 110 s.
   - The plan already says the timeline helper exists "so the carrier's numbers exist once".

7. **Reuse `REPLAY.placed()` for the pin (minor).** `level1_slice_replay.gd:108` `placed(scene_path)` already returns `{section, trigger (effective), delay, offset, rel}` per placed line, which is exactly the pin's shape. Use `placed(WaveBuilder.CARRIER)` for `EXPECTED_PH10_CARRIER` and for the guard's non-vacuity line. Keep `lines(section)` only for the mutated-section boundaries (58.0 s, x 550, 95.0 s, the extra carriers), which `placed()` cannot see.

Not findings (checked and fine):
- Adding the carrier to the 65.0 s wave moves no effective trigger and no wave index. The fire-density schedule row, the drone and specialist pins, and `_ph8_intervals` are untouched.
- `deaths` empty, which is stronger than t11's covered-only filter, is safe: nothing in the 64–86 s slice can hurt a carrier part (enemy contact boxes mask 128 only; the 85.0 s corvette has no time to launch).
- The real-ray sanity row on the replay's own 78.0 s rays is an acceptable stand-in for §2.13's standalone ray: t11 set that precedent at `:794-831`. Note that `_check_ray_edges()` will skip the 78.0 s end edge, because 85.56 + `EDGE_GUARD` > stop. The sanity row's "last lethal tick < 78.0 + `lit_seconds()`" and `lethal_at_stop == 0` are what cover the end, which is one more reason for finding 3.

## Round 2

VERDICT: APPROVED

All seven round-1 findings are resolved in the revised `3-plan.md`. I re-checked each one against the code, not the plan's word. The revision introduces no blocking problem. Two notes for the implementer follow; neither needs another review round.

**Round-1 findings**

1. **Resolved.** Drone intervals now start at spawn and end at spawn + worst life + lifetime (`3-plan.md:43-47`). The tight per-bay windows stay only in the attack row, which asserts no PANIC (`3-plan.md:76-78`).
   - This bound is honest. `carrier_hangars.gd:118-129` `emergency_deploy()` ignores the clock and the view. `carrier_brain.gd:116-117,526` enters PANIC only on `_core_exposed()`, so `is_core_exposed()` false at the stop does prove no emergency deployment happened.
   - The C3 arithmetic holds. `level1_drone_concurrency.gd` `peak_intervals()` samples at starts with `start <= t < end`. Today's planet_approach is 7 capable / 9 all (`test_level1_drone_spawns.gd:177-181`, legacy 6). Even with all four new intervals overlapping, that gives at most 10 of 12 and 13 of 15.
   - The budget counts from spawn (`swarm_drone_brain.gd:207,254`; `engagement_budget.gd`), so the existing lifetime formula applies to a hangar child too.

2. **Resolved.** The plan now asserts a computed clearance floor, `>= LaserRay._HAZARD_PAD`, and the measured sway against the leash (`3-plan.md:69-72`).
   - The floor formula matches what the replay actually measures. `level1_slice_replay.gd:430-444` takes the gap between the root `HurtBox` AABB and `danger_rect()`, which is `_BEAM_WIDTH` 56 wide (`laser_ray.gd:76,177,309`).
   - The hull is 176 wide (`carrier.tscn:37,98-104`), the sway is clamped to ±30 (`carrier_brain.gd:434`), and the carrier never rotates in CROSS (`carrier_brain.gd:17,406`).
   - So the floor is 200 − 30 − 88 − 28 = 54.

3. **Resolved.** The Risks section now allows only share / memoise and never an assertion (`3-plan.md:121-122`).

4. **Resolved.** The figures are corrected in both files (`3-plan.md:65-67`; `1-context.md` slice-replay row): offset +220, spawn y 60, freed at about 78.8 s.
   - The new `player_offset` gives a target of −430, clamped to −380.
   - `follow_speed` 12/s (`arena_camera.gd:58,145`) converges well inside the 1 s `PRE_ROLL`.
   - World anchoring (`carrier.gd:76`) subtracts the view centre, so shake cancels out of the spawn x.

5. **Resolved.** `k` is now derived (`3-plan.md:87-89`).
   - Every new interval contains the peak instant, so the peak becomes at least all + 4k ≥ floor(2.5 × legacy) + 1.
   - When inserting the boundary wave, put it in list order. `drone_intervals()` reads the effective trigger, while `squad_intervals()` reads the raw `trigger_time` (`level1_drone_concurrency.gd`). The two agree only while the wave list is monotone, which the shipped planet_approach list is.

6. **Resolved.** `swarm_lifetimes()` moves into `level1_drone_concurrency.gd`, replacing `test_level1_drone_spawns.gd:363` `_c3_lifetimes()`, and both files read it (`3-plan.md:42-43`).

7. **Resolved.** The pin and the guard read `REPLAY.placed(WaveBuilder.CARRIER)`.
   - `level1_slice_replay.gd:108` returns `{section, trigger (effective), delay, offset, rel}`.
   - `wave_builder.gd:300` defines `CARRIER`.
   - The guard to extend is at `test_engagement_deadline.gd:974-988`.

**New checks on the revision (no change needed)**

- The high stub (`level1_slice_replay.gd:302` places it once, from the camera centre) does not make `deaths` empty vacuous or unsafe. The slice from 64.0 s excludes the 62.0 s jammer and every earlier wave.
  - Nothing in the slice can hurt a carrier part: enemy rounds never hit enemies, and the hull has `collision_mask` 0.
  - The 85.0 s corvette spawns after the carrier is freed at about 85.6 s.
  - The carrier's 78.0 s overlap is real. At 81.56 s its hull spans y 802–1082, inside the 78.0 s beams (y −380..1156), so the clearance will be finite.
- The spill row now uses the same spawn-based child end (≈ 93.7 s against 110 s). Its boundary at 95.0 s fails: 95 + 20.61 > 110. The 58.0 s and world-x-550 boundaries of `_carrier_column_conflicts()` are both flagged by the stated threshold of 186 px.
- `TurretMount.round_fired` (`turret_mount.gd:42`), `Carrier.hangars()` / `battery_mounts()` / `bow_mount()` / `missile_mount()` / `is_core_exposed()` (`carrier.gd:164-187`) and `RocketBatteryMount.pool_specs()` all exist as the plan uses them.

**Notes for the implementer (non-blocking)**

- **N1. The clearance floor will be hit exactly. Give it the same tolerance as the sway check.**
  - In the 78.0 s lethal window (81.56–85.56 s) the stub, at y ≈ −100, is 1000+ px above the carrier. So `_sway_target_x()` (`carrier_brain.gd:409-434`) asks for `player.x + |dy| / tan(half)`, which is clamped to anchor + 30 = 780. The P-controller (`carrier_brain.gd:402`) converges onto that value from below.
  - The measured lethal gap to the 950 column is then 950 − 28 − (780 + 88) = **54.0**, equal to the floor up to float error.
  - Assert `clearance >= floor − 0.5` (the `+ 0.5` epsilon `3-plan.md:71` already uses for the sway), or the row may fail spuriously at 53.9999.
  - It also means the lethal-margin figure for DECISIONS will be exactly the floor. That is expected and should be recorded as such: the parts margin from the static model is 70 px. The real hangar edge is at 92 px, so the true part gap is 50 px, still clear of the strip.
- **N2. `1-context.md:13` (`carrier_hangars.gd` row) still says "Launch times for the drone gate: earliest = spawn + 3.0 (+ 4.0) + 0.8".** That contradicts the revised §2 and is exactly the round-1 finding-1 model. Reword it to "attack row only; the drone gate starts at spawn" so the implementer is not misled.
