VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` (t16, Space Fortress geometry weapons) against the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` ("For every task", §2.5.5, §2.5.6,
§2.6, §2.7.1–§2.7.7, §2.15, §2.16), `CLAUDE.md`, `tests/README.md` and the code it touches.

The design follows the epic faithfully. Scenes, config group, `CoreRingPool` built in `_ready()`, the FADE tick, owner-ticked clocks, snapshots and the lever order
all match, and nothing is reinvented. Four problems block approval. Three existing t6 movement rows will go red and the plan does not mention them. Row 9's
pool check cannot pass with the helper the plan names. The 15° gap boundary does not fail for one of the two players. The +3.0 s gate allotment is not
credibly accounted for.

## Blocking findings

### B1. The plan breaks three t6 rows in `test_space_fortress.gd` and does not list them
- **Spin bookkeeping is level-triggered.** Plan: "no volley spoke ACTIVE while one runs → `end_spin()`". `FortressBrain.tick()` (`fortress_brain.gd:120-133`)
  calls `_face()` before `_tick_weapons()`. So with t16's bookkeeping after it, a spin started by hand with `begin_spin()` turns for one tick and is then
  ended. `test_spins_volley_alternating_and_critical_continuous` (`test_space_fortress.gd:1169-1203`) does exactly that: it calls `b.begin_spin()` and expects
  60 ticks at `beam_spin_rate`, then does the same for the `turn_lerp` 0.3 boundary on `g`. That row fails.
  - The epic's wording is edge-triggered: "`begin_spin(direction)` when its beams turn ACTIVE and `end_spin()` when they FADE" (§2.7.2).
  - Make the bookkeeping fire on the transition: end the spin when a volley that this brain started leaves ACTIVE. Do not end it on every tick where no spoke
    is ACTIVE. Alternatively, keep a "spin started by a volley" flag. Either way `begin_spin()` / `end_spin()` stay a usable public seam (t6 built them
    for this).
- **Real volleys now fire inside t6's long hand-ticked runs in `shields_exposed`.** `_mover_spawn` starts the fortress engaged, with a target, in view, so
  the spoke clock runs. A volley goes ACTIVE at 8.0 + 1.2 = 9.2 s and spins at 0.5 rad/s. That is faster than either facing-rule rate (0.22 Open Space,
  0.30 Assault).
  - `test_the_strongest_sector_turns_to_the_player_at_exactly_the_turn_rate` (`:876-896`): destroying spread and pulse enters `shields_exposed` (2 WEAPON
    losses). The 120° turn takes about 9.5 s in Open Space and the 180° turn about 10.5 s in Assault and 14.3 s in Open Space. Each crosses 9.2 s, so
    `misses` becomes greater than 0.
  - `test_assault_enters_holds_bobs_and_never_moves_x` (`:1085-1135`): 15 s in `shields_exposed` asserts `max_turn <= assault_turn_rate * DT` and
    `_side_error < 0.01` at the end. The volley spin breaks the first. The 1.25 rad swing, unwound at 0.30 rad/s, ends after 15 s and breaks the second.
- **What the plan should add.** These rows test movement, so the fix is to keep the geometry weapons quiet in them. Give `_mover_spawn` a `props`
  dictionary like `_spawn` (`:93-100`) and write `spoke_period` / `ring_period` / `core_ring_period` 1e6 on the private config. Add this to Build sequence
  step 1, and name every existing row that is touched. Also sweep the other movement rows that hand-tick past 8 s in a later phase for side effects:
  `:958`, `:982` (60 s in core_exposed), `:1015` (critical, 1000 ticks) and `:1054`.

### B2. Row 9 cannot pass with t7's `_expire` (pool exhaustion)
- **Core-ring rounds are never returned.** `_expire` (`test_fortress_weapons.gd:117-130`) only returns rounds that `_watch` recorded from
  `mount.round_fired` (`:103-105`). Core-ring bullets come from `RadialAttackPattern.fire()` → `pool.acquire()` (`radial_attack_pattern.gd:78`), not from a
  mount, so they would never be recorded or returned.
- **`_life()` gives the wrong life.** It returns `ProjectileLifetime.max_time` = 18 s for any `EnemyBullet` (`:85-89`). At 18 s the 72-round pool needs
  12 × ceil(18 / 2) = 108 and runs dry at the 7th ring.
- **What the plan should specify.** Record every core-ring acquisition, for example by diffing `CoreRingPool._active` after each tick. Expire each one at the
  life the pool was sized for: min(`max_time`, `max_distance` / `core_ring_speed`) = 11.43 s, read from the scene the same way the root does.
- **Note the zero margin.** The pool holds exactly 72 at ring 7 (t = 14.0 s: rings 2–6 plus ring 7). The margin is 0.57 s of time, not spare rounds. The
  row depends on ring 1 returning at 13.43 s, before ring 7 fires.

### B3. The 15° ring-gap boundary does not fail for the Open Space ship
- The predicate is `deg_to_rad(gap_deg) × (176 + r_p) ≥ 4 r_p`.
  - Assault fighter, r_p 13.5: 0.2618 × 189.5 = 49.6 < 54, so it fails as intended.
  - Open Space ship, r_p 11: 0.2618 × 187 = 48.96 ≥ 44, so it **passes**.
- If the row asserts the boundary per player, the boundary assertion itself fails.
- State that the boundary is evaluated as the conjunction over both players, or with the larger r_p. `test_energy_ring.gd::_player_r_p()`
  (`test_energy_ring.gd:173-190`) takes the larger. The epic §2.7.6 says "for both players … Boundary: a 15° gap fails it".

### B4. The gate-time risk is not credibly handled (allotment +3.0 s, escalation at 4.5 s)
The plan's only mitigation targets the density loop. It leaves out three costs that together plausibly exceed 3.0 s:
- **Fixed cost per fortress instance.** Every instance now builds 72 more pooled `EnemyBullet`s, 4 beams × 6 `Line2D` and a ring. t7 recorded that its 68
  pooled rounds alone put about +0.75 s on `test_space_fortress.gd` (3.05 → 3.8 s; `tests/README.md:722`). About 130 fortress spawns across eight test files
  (`test_space_fortress.gd`, `test_fortress_weapons.gd`, `test_base_enemy.gd`, `test_config_instance_isolation.gd`, the roster gates) pay it again.
- **Real-physics rows: 2 rows × 2 harnesses at 8×.** Each "never hits the owner set / a part" assertion needs a full ACTIVE (2.5 s) or EXPANDING (2.13 s)
  window, about 3.5–4 s of simulated time, or roughly 0.5 s wall each. The ring row also depends on the brain's `rng` gap draw: a target inside a 50° gap is
  skipped for that ring, and the next ring is about 3.3 s later.
- **Hand-ticked rows 7–10 in both harnesses.** They add roughly 20 000 more brain or full ticks (20 s quiet windows, 30 s of core rings, and so on).

Require the plan to:
1. Estimate each item.
2. Measure `test_space_fortress.gd` before and after Build sequence step 4, which isolates the fixed cost.
3. Name these mitigations:
   - stop positive rows at first evidence;
   - bound negative checks to one window;
   - seed `rng_seed`, or choose target bearings so the gap cannot cover both targets;
   - share one real-physics world for the spoke and ring rows (both run in `core_exposed`);
   - use t7's coarse 0.05 s brain step (`test_fortress_weapons.gd:294`) for the "nothing for 20 s / 30 s" windows;
   - use 16× only after the wall-vs-CPU check.

## Non-blocking findings (fix in the revision)

- **N1. Density battery set.** `_ladder_to` (`test_fortress_weapons.gd:159-177`) enters `shields_exposed` by killing `battery_sweep` + `battery_artillery`. The
  density row needs sweep + **missiles** (epic §2.7.6). Say that the row destroys `battery_sweep` and `battery_missiles` first, which itself enters
  `shields_exposed`, and only then calls `_ladder_to`, which skips steps already reached.
- **N2. Row 10 EMP negatives can pass vacuously.** The window is `seconds × emp_factor` (0.4). A 4 s EMP is a 1.6 s window, shorter than `core_ring_period`
  2.0. So "no core-ring round is acquired" and "no spoke or ring starts" can pass because nothing was due anyway. Pick the EMP length, or shorten periods on
  the private config, so a core ring, a volley and a ring are each due inside the window. Assert that this is so, for example from the countdowns.
- **N3. Real-physics spoke geometry.** After `_ladder_to(core_exposed)` the south sector is presented (1.0 vs 0.5), so `Spoke1` (local 90°) faces the player.
  The volley spin starts at ACTIVE, and `ignite_grace` 0.1 s × 0.5 rad/s = 0.05 rad. The hit band reaches `hit_half_width` + r_p ≈ 25.5 px, so the player
  must be within about 500 px. State the placement so the row does not depend on luck.
- **N4. Long hand-ticked critical rows exhaust `CoreRingPool`.** In existing rows, critical runs over 12 s with rounds never returned, for example
  `test_space_fortress.gd:1119` (15 s of critical = 7 rings = 84 rounds). Each prints one "Pool exhausted" warning per fortress. It does not fail anything,
  but it adds gate output (the 1 MiB rule). The B1 props remove it.
- **N5. Docs.** Build sequence step 7 lists the docs but does not say to invoke the `updating-project-docs` skill, which `CLAUDE.md` makes mandatory for new
  scenes or mechanics. It also omits the `CLAUDE.md` line for the fortress weapons.

## Checked and fine

- **FADE tick is reachable.** `BaseEnemy._physics_process` returns early only from itself (`base_enemy.gd:126-139`). An override that calls `super(delta)` and
  then tests `is_ai_suspended() or is_emp_disrupted()` (`:163`, `:193`) runs its own code on every EMP and dying tick.
  - On the tick the window ends, `_step_emp` clears it before the brain ticks, so nothing is ticked twice.
  - `_spawn`'s `set_physics_process(false)` does not matter, because rows call `f._physics_process(DT)` by hand.
- **Hand ticks never cast for cover.** `enemy_beam.gd:302` casts only when `Engine.is_in_physics_frame()`. Hand-ticked rows that never `await
  physics_frame` are deterministic, and the real-physics rows cast as intended. The hull's root layer is 0 and its RID is excluded (`:307-308`).
- **Launch counting is honest.** Every pool is returned each tick (direct `_recycle`, `bullet_pool.gd:108-119`; the deferred duplicate is a no-op at
  `:112`). So `_active.size()` after a tick equals that tick's acquisitions (`:83-100`). Rocket pools are `BulletPool`s too.
- **Owner set.** Parts join only `enemy_parts` (`enemy_module.gd:56,98`), which is not in `EnergyHitScan.VICTIM_GROUPS` (`energy_hit_scan.gd:17`). The root
  is the host and is in the owner group (`space_fortress.gd:97-99`).
- **Durations fit the periods.** Ring timeline 1.0 + 640 / 300 + 0.15 = 3.28 s < 3.5 s; spoke 1.2 + 2.5 + 0.15 = 3.85 s < 6.0 s. So `start()` is never
  ignored at the shipped numbers (`energy_ring.gd:98-100`, `enemy_beam.gd:154-156`).
- **Pool sizing follows production precedent.** It reads `ProjectileLifetime` through `EnemyBeamScenes.export_of_scene` (`burst_cannon_mount.gd:43`).
  `enemy_bullet.tscn` authors `max_time` 18 and `max_distance` 2400 on its own `ProjectileLifetime` node, so the reader sees them. The container is the
  grandparent (`bullet_pool.gd:66`), so the bullets land in the fortress's parent.
- **Lanes predicate.** At step 0.24 and spacing 2π / 12 the five lanes are distinct, with a largest gap of 0.1964 / 0.5236 = 0.375. Both boundaries (spacing
  / 2 and spacing / 3) fail the same predicate.
- **Fairness numbers.** Spin × (176 + 250) = 255.6 px/s ≤ 0.8 × `cruise_speed()`: 288 for the fighter, 336 for the ship. `cruise_speed()` exists on both
  (`player_fighter.gd:128`, `player_ship.gd:483`).
- **§25 literals and other gates.** Row 6 / 12 literals and the `BUILT_KEYS` / ATTACKS-exemption change (`test_space_fortress.gd:42`, `:510`) match §2.5.5.
  `test_enemy_bullet_lifetime.gd:98` is the right place for the 210 px/s source (2400 / 210 ≤ 18).

## Round 2

VERDICT: APPROVED

I re-checked revision 1 of `3-plan.md` against each round-1 finding and against the code. All four blocking findings and all five non-blocking ones are
answered. The revision broke nothing that blocks implementation. The notes below are conditions on the implementation, not a reason to send the plan back.

### Round-1 findings, re-checked

- **B1. Resolved.**
  - The spin bookkeeping now fires on the transition (plan l. 53-57). The brain remembers the volley's spokes, starts a spin when one of them first turns
    ACTIVE, and ends it only when none of them is ACTIVE any more. A spin started by hand with `begin_spin()` is never touched. So
    `test_spins_volley_alternating_and_critical_continuous` (`test_space_fortress.gd:1169-1203`) and the `begin_spin()` in the EMP row (`:1212`) keep
    working. In `critical`, `_face` uses the continuous spin first (`fortress_brain.gd:456-457`), so a volley's `begin_spin(0)` there only advances the
    alternation and is harmless.
  - The quiet `_mover_spawn` (l. 69-75) covers every movement row I flagged (`:876`, `:958`, `:982`, `:1015`, `:1054`, `:1085`). The `.tres` stays untouched,
    because `_mover_spawn` writes to the config copy that `ShipConfig.privatise()` made in `_init()`. That is the same thing `_spawn` already does
    (`:93-100`).
  - The §25 row uses `_spawn`, so it sees the shipped values.
- **B2. Resolved** (l. 110-113). The row records each core-ring launch as a new entry of `core_ring_pool()._active` and returns it at 11.43 s.
  - When appended to `rec["live"]`, t7's `_expire` returns those rounds correctly. It emits `expired` and then calls `_recycle` on every `BulletPool` child
    (`test_fortress_weapons.gd:126-129`). A pool's `_recycle` ignores rounds it does not own (`bullet_pool.gd:112`).
  - The timing margin the plan states is right: ring 1 is returned at tick about 806, before ring 7 fires at tick 840. After ring 7 the pool is exactly
    full: 60 rounds from rings 2–6 plus 12.
- **B3. Resolved** (l. 125-128). The boundary is now the conjunction over both players, and the row asserts each player's result. That boundary can fail
  and cannot pass vacuously.
- **B4. Resolved enough to proceed.** The new *Gate time* section (l. 143-155) has per-item estimates, a measured trigger on `test_space_fortress.gd`, coarse
  steps for the negative windows, one shared real-physics world, and an escalation line. Its real-physics figure is low; see note 2.
- **N1–N5. Resolved.**
  - N1 (l. 131-132): `_ladder_to` skips steps already reached, so destroying sweep and missiles first never also kills the artillery
    (`test_fortress_weapons.gd:163`).
  - N2 (l. 119-120): an 8 s window is longer than 6.0, 3.5 and 2.0 s. The countdown accessors the row reads are not yet in the Brain design list, so add
    them when building it.
  - N3 (l. 98-99): with all five batteries dead, sector strength is 0 to 0. The tie keeps south (`fortress_brain.gd:274-275`), so `Spoke1` does face the
    player.
  - N4 and N5 are answered.

### Notes for the implementation (no re-review needed)

1. **Prewarm contingency (l. 146-149), only if taken.** Three conditions:
   - **Defer it.** Run the prewarm with `call_deferred`, like every other tree change made from `_on_phase_entered`. A generator's death usually lands
     inside a physics flush (`space_fortress.gd:224`), and the prewarm adds 72 `Area2D`-bearing rounds to the tree.
   - **Make it idempotent, and also run it on entering `critical`.**
   - **Check the t7 rows that call `brain.on_boss_phase(&"critical")` directly.** `_gate_peak` (`test_fortress_weapons.gd:236`) and the 30 s row (`:455`)
     skip the root's handler, so they would meet an empty pool and get a "Pool exhausted" warning. Give them the quiet props.
   - Also, the quiet props l. 74 puts on "the 30 s critical-fire row" do nothing there: that row ticks one mount directly (`:463-466`), never the brain. The
     row that does tick the brain in `critical`, `_gate_peak` (600 ticks), stays under the pool: 5 rings × 12 = 60 < 72. No change needed today.
2. **The shared real-physics row runs longer than 4.5 s of simulated time.**
   - One volley takes 0.3 + 1.2 + 2.5 + 0.15 = 4.15 s.
   - A ring reaches 400 px about 0.3 + 1.0 + 1.33 = 2.6 s after it arms.
   - A second ring cannot start until the first is in FADE, about 3.6 s per ring cycle.
   - So requiring "two rings have run" means about 6–7 s, or about 0.85 s wall per harness. That still fits the 10 s cap and the 4.5 s escalation line.
   - Require the second ring only when the first missed a target in its gap. The owner-group fixture at 250 px is on both the spoke line and the ring's
     path, so one lit volley and one ring that passed 400 px already cover every negative assertion.
3. **Seed before the brain's `_ready()`.** `EnemyBrain` seeds `rng` in `_ready()` (`enemy_brain.gd:57-60`), so write `rng_seed` on the brain before
   `add_child`, or reseed `brain.rng` afterwards.
4. **Outsider fixture bearing.** A lit `Spoke1` sweeps about ±72° during one volley (0.5 rad/s × 2.5 s). "Away from every spoke" therefore means local about
   0° or 180°, not the 45° diagonals. A spoke hit on the outsider is allowed by design, but it would muddle the failure messages.
5. **Repeated `start()` calls.** With `spoke_period` / `ring_period` 0.3, the countdown calls `start()` every 0.3 s while a shot is running. Those calls are
   ignored (`enemy_beam.gd:155`, `energy_ring.gd:99`). Make sure an ignored call does not reset the remembered volley or the spin flag. The simplest way is
   to remember spokes only when `start()` actually moved them to TELEGRAPH.
6. **EMP bookkeeping.** In `on_emp_started()` / `silence()`, also clear `_volley_spinning` and forget the volley, so that leaving the window leaves no stale
   state.
