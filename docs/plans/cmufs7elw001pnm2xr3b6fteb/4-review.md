VERDICT: CHANGES_REQUESTED

# Plan review, round 1: Enemy rework, phase 5 (Missile Corvette, rockets, Support/Shield Ship)

Reviewed `3-plan.md` (Revision 1), `1-context.md`, `2-research.md` and `tasks.json` against the code at `5a2c494`
(`agent/auto-dev`), `CLAUDE.md`, `tests/README.md`, `DECISIONS.md` (Phases 1–5 sections) and the four earlier reports.

**What holds up.** The plan covers the whole scope (§6.1, §6.2, §11.2 minus the Hijack Pulse, §13.2, §23, §40, §41 Ph3
items 4–5, §37 Support + Ram). It builds on the earlier phases and explains each place it departs from them: P-15 closed
with reasons; owner-distance lifetime dropped and logged; container injection deferred again; rocket tuning moved into
the rocket scenes with a reason. It reuses what already exists: `EnemyOrdnance`'s contract by shape, `ContactBlast`,
`BulletPool.persist_after_owner_death`, `ProjectileLifetime`, `TargetInfo.intercept`, `Steering.turn_toward`,
`BurstClock`, `AnchorIdle`, `EngagementBudget`, `SpecialistExitProbe.corridor_starts()` and the `ArmorPlate._resolve`
shape. The HurtBox absorb hook really is the smallest hit-aware change: `HurtBox._on_area_entered` is the only place that
holds the `HitBox` (`global/components/hurtbox_component.gd:12-18`). I checked the hub geometry: the anchors (1344, −1344)
and (−1202, −1202) match `sector_hub.gd:46-78`, and the corvette sits 1345 px from the Razor anchor and 1353 px from the
Gatling anchor. Level-1 placement rows also exist where the plan says: the deep_space rams at 26.0 s
(`level_1_director.gd:449-451`) and the planet_approach ram triple at 28.0 s. The research weighs tradeoffs and labels
its judgements.

**Why not approved.** Four parts of the rocket and escort design contradict the shipped code:
- The player's missiles would be silently eaten by enemy rockets.
- A "direct hit = impact + blast" cannot happen against the player's 0.5 s i-frames, which also inverts the Delayed
  Warhead's damage.
- A launcher can run over its own unarmed rocket. On the plan's own rail fallback it does so every time.
- The escort tow can drag a Sniper through its "stationary and frozen" LOCK.

Separately, the gate-time budget gives the whole epic about 15 s, but a single Phase 4 level task cost about 17 s. The
time-heavy late tasks will predictably hit the cap. Each problem has a cheap fix at plan level and an expensive one
mid-implementation.

---

## Findings

### 1. (blocking) Player missiles are consumed by enemy rockets; the plan says they "pass through" — t5
- **Plan:** `3-plan.md:363`: "Player rockets (layer 32) pass through enemy rockets (their HurtBox masks 64 only)". The
  t5 row at `:432`: "a real player homing rocket passes through it (rocket alive after)".
- **Code:** the player homing and warhead missiles' `HitBox` is layer 32, **mask 513** (`homing_missile.tscn:54-55`,
  `warhead_missile.tscn:60-61`). The enemy rocket's own HurtBox sits on **layer 512** (plan `:332`), so the player missile
  detects it. `homing_missile.gd:51-54` then calls `ArmorQuery.deflects()`. The target answers neither duck type
  (`armor_query.gd:20-25`), so the missile calls `queue_free()`. The enemy rocket's mask 64 only means the enemy rocket
  takes no damage. Overlap detection runs one way per area; masks are not symmetric.
- **Result:** a homing volley crossing a salvo is silently eaten and leaves every enemy rocket alive. The t5 row as worded
  ("rocket alive after") would pass on exactly that bug.
- **Fix:** decide the interaction explicitly. Recommended: a player missile and an enemy rocket destroy each other.
  - Give the enemy rocket's HurtBox mask `32 | 64`.
  - Make the rocket decide in its own `HurtBox.area_entered`, in the `ArmorPlate._resolve` shape, and ignore any
    `HitBox` whose owner is an `EnemyRocket`. That keeps C2: sibling impact HitBoxes are on 32 too.
  - Rewrite the t5 row to: "a player homing missile and an enemy rocket both expire; no blast".
  - Alternatively, keep "pass through" and make the player missiles skip `EnemyRocket` areas, but say which and test it
    from the player missile's side.

### 2. (blocking) "Direct hit = impact + blast" cannot happen on the real player, and it inverts the Warhead — t5, t6
- **Plan:** `3-plan.md:358-360` and the t5 row at `:439`: "the player takes `impact_damage + blast_damage` on a direct
  hit".
- **Code:** `PlayerBase._apply_damage` starts invincibility after **every** hit (`global/entities/player_base.gd:105-124`;
  `invincibility_sec = 0.5` at `:23`, pinned in `test_player_damage_chain.gd:86`). `ContactBlast` attaches at the next
  flush (`contact_blast.gd:36-48`), a frame or more after the impact. The blast therefore always lands inside the
  i-frames, so a direct hit deals `impact_damage` only.
- **Warhead consequence:** impact 12 against blast 30 (`:391`) means a direct hit hurts the player **less** than a near
  miss.
- **Shield consequence:** with i-frames off (a test fixture), a direct hit would instead spend two player shield charges.
- **Fix:** give the player one damage source per rocket.
  - Recommended: the impact `HitBox` sits on **32 only** (friendly fire). Its mask stays `1 | 128 | 512` so it still
    detonates on the player. Player damage comes from the `ContactBlast` alone, so a direct hit and a near miss both
    deal `blast_damage`.
  - Re-tune the table to match (the blast becomes the player-facing number).
  - Assert the t5 row on the **real** `player_ship.tscn` / `player_fighter.tscn`, not a bare hurtbox stub.

### 3. (blocking) A launcher can overrun its own rocket; "never hits its own launcher" is not guaranteed — t5, t7
- **Plan:** `3-plan.md:343-346` says arming at `arm_distance` "from its launch point" means it "never hits its own
  launcher". Launch speeds are 100–140 px/s (`:387-391`), slower than the corvette's `max_speed` of 210 (`:498`).
- **Rail fallback:** it fires a DUMB rocket straight DOWN every 2.5 s while on a rail (`:515-516`). Rails move at
  `straight(speed) × WORLD_SCALE`, typically ≥ 330 px/s downward. The railed corvette therefore passes its own unarmed
  rocket every time.
- **What happens then:** the rocket arms 52 px from a launch point that is now behind or inside the hull. Its `HitBox`
  (layer 32) is detected by the corvette's own HurtBox (runtime mask 1121, `base_enemy.gd:75-76`). Its mask 1 also sees
  the corvette's body, which is on default layer 1 (`bomber.tscn:63` shows no layer override, the specialist template).
- **The planned "launcher exclusion" cannot help:** the rocket's handler can ignore the launcher, but the launcher's
  `HurtBox` decides on its own and emits `received_damage` regardless (`hurtbox_component.gd:12-18`).
- **Gap in the tests:** the t5/t7 tests use a stationary fixture launcher and a stationary suspended corvette, so
  neither can see this.
- **Fix:**
  - Launch velocity inherits the launcher's velocity: `launcher.velocity + dir × launch_speed`, the standard missile
    rule.
  - Arm on distance from the launcher's **current** position (> launcher radius + `body_radius` + margin), not from the
    launch point.
  - Add rows for: a launcher moving at `max_speed` along the launch direction; a corvette on a `straight()` rail firing
    its fallback.
  - Both rows assert launcher HP unchanged.

### 4. (blocking) The escort tow can drag a ward through its telegraphed attack — t3, t13
- **Plan:** `accept_tow` refuses only when the ward is suspended, has no mover, or is boosting (`3-plan.md:285`).
- **Sniper:** LOCK is "stationary and frozen" (`sniper_brain.gd:5`, `:21`), but the shot leaves from the **current**
  muzzle toward `lock_point` (`:560-563`). With `escort_tow_ratio` 1.25 against a ward whose brain requests nothing, the
  ward slides at its `max_speed` (`enemy_mover.gd:185-188`). A 0.5 s LOCK moves the muzzle roughly 100 px off the line
  the player was shown.
- **Other phases affected:** Ram WIND_UP (not yet boosting), Bomber RUN and the corvette's own TELEGRAPH/SALVO are hit
  the same way. Ph4's fairness rule (telegraph = attack) is gated nowhere for a towed ward.
- **Also:** `For every task` (`:46`) promises "false when … brainless", but §2.4 omits the brain check. With no brain,
  `BaseEnemy._physics_process` returns before `mover.step()` (`base_enemy.gd:103-108`). The nudge would be accepted and
  never applied.
- **Fix:**
  - Add a duck-typed `accepts_tow() -> bool` on `EnemyBrain` (default true). It answers false in committed or
    telegraphed phases: Sniper DECOY/AIM/LOCK/FIRE, Ram WIND_UP/CHARGE, Bomber RUN, corvette TELEGRAPH/SALVO.
  - `accept_tow` checks it, and also checks `_brain != null`.
  - ESCORT then waits or interposes only.
  - Add t3/t13 rows: a locking sniper and a winding-up ram refuse the tow, and their position is unchanged across the
    phase.

### 5. (blocking) The gate-time budget cannot hold this epic, and nothing allocates it — t1, all test-adding tasks
- **Plan:** "this epic's new tests together may add at most the headroom t1 freed minus 15 s" (`3-plan.md:76-77`, `:915`).
  With t1's target of 30 s, the whole epic gets **15 s**.
- **Evidence it is too little:** Ph4's t22 alone, one level-placement task, took GUT time from ~240 s to 256.8 s
  (`DECISIONS.md:1715`).
- **What this epic adds:** two dual-mode enemy specs; a rocket family with real-physics rows; shield real-physics rows;
  corridor-wide exit probes for two new kinds; attack-in-budget replays through a real `WaveManager` for five placements;
  and hub 8× rows.
- **No allocation:** §4.1 says "a task that would exceed its share", but no shares are defined anywhere.
- **Wall clock not measured:** the ~300 s cap is wall clock (import + boot + GUT), yet the plan budgets only GUT time.
  `/agent/verify.sh` has no 300 s timeout of its own; the cap is the harness's.
- **Likely outcome:** t17 (and probably t12/t16) exceed the budget and escalate late.
- **Fix:**
  - t1 records import + boot time as well as per-file GUT time.
  - The plan carries a per-task GUT-time allotment table estimated from Ph4 analogues (e.g. Ph4 t10, t21, t22). Size
    t1's target from that table rather than a flat 30 s, or put owner question 4 (raise the cap?) to the owner **before**
    t1, not as a fallback.
  - Make t3 and t4 depend on t1. Today they have no dependency (`tasks.json` t3/t4 `dependsOn: []`), so they can land
    in the middle of t1's before/after measurement and spend budget before it exists.
- **On t1's means:** they are sound and do not weaken tests. They are the 8× clock, computing an identical replay once
  in `before_all` (`test_fighter_squad.gd:144-170` `_run` is replayed per test) and dropping unread bookkeeping, with an
  explicit "never lower a tick count, duration, sample count or start grid". Keep them.

### 6. (minor) One enemy rocket cannot break a Ram plate; the t5 row says it does — t5
- **Plan:** `3-plan.md:437`: "a real `ram_corvette.tscn` plate on the path breaks (`plate_broken` once)".
- **Code:** plates have **50 HP** (`ram_corvette_config.tres:10`). `ArmorPlate._resolve` applies `hit_box.damage` and
  breaks only at 0 (`armor_plate.gd:126-130`). Enemy rocket impacts are 8–18 (`:387-391`), so a plate needs 3+ rockets.
- **Fix:** the row asserts plate HP drops by `impact_damage` and the rocket is consumed, and that `ceil(50 / 18)` = 3
  rockets break it. Owner question 1 ("rockets break plates") should say "wear down, about three rockets".

### 7. (minor) `enemy_view_rect()` built on `get_screen_center_position()` is fragile in tests — t4
- **Plan:** `3-plan.md:302`.
- **Problem:** `Camera2D.get_screen_center_position()` returns the centre cached at the camera's last scroll update. That
  update happens only for the current camera, in its own process step, so a test that sets `offset = (0, -300)` and
  reads the rect at once can get a stale value. Hand-ticked dual-mode specs never process the harness camera at all
  (`enemy_ai_harness.gd:51-55`).
- **Fix:** the project's own convention for "the camera's current view" is `cam.global_position + cam.offset` (class doc
  `arena_camera.gd:10-15`; `level_1_director.gd:140`). Use that, size `viewport / zoom`, and the t4 row becomes
  deterministic.

### 8. (minor) Two corvette test rows cannot pass as written — t8
- **Plan:** `3-plan.md:562-564`.
- **The `min_range` row:** "never inside `min_range` for more than 1.0 s cumulatively when the stub closes at 200 px/s".
  - Against a closing threat, `Steering.break_contact` doubles its lateral share (`steering.gd:200-205`). The radial
    speed is about `210 / √(1 + 1.2²)` ≈ 134 px/s, below the stub's 200.
  - The corvette is inside 380 px within about 4 s of an unbounded chase in Open Space, and sooner against Assault's
    corridor edge.
- **The bearing row:** "bearing changes by ≥ 60° over 10 s" can net to about 0 with reversals every 4–7 s (`:536`).
- **Fix:** bound the chase (the stub closes for 2 s, then stops; the corvette is back outside `min_range` within N s).
  Measure arcing as cumulative |Δbearing|.

### 9. (minor) A projected shield on an armoured ward drains on hits the hull deflects — t2, t12
- **Code:** the HurtBox asks the absorber before anything else (plan `:199-201`). An armoured Ram answers
  `deflects_hit` true for every projectile (`ram_corvette.gd:84-91`). A player bullet therefore costs shield points and
  flares the arc, then flies on through the hull.
- **Where it shows:** this is the hub pairing (`:787-789`) and the Support + Ram pairing (R5.27).
- **Fix:** `absorbs_hit` returns false while the host refuses the hit (host `deflects_hit(hb)` / `is_armored()`). Or the
  support does not project onto an armoured ward. Add a row with an armoured Ram.

### 10. (minor) The rocket trail would come out of the nose — t5, t9
- **Code:** `RocketTrail` emits along local +Y "for a rocket whose nose points in local −Y" (`rocket_trail.gd:12-13`,
  `:31-32`).
- **Plan:** draws rockets nose-down with `rotation = heading.angle() − PI/2` (`3-plan.md:336-337`), so local +Y is the
  nose.
- **Fix:** use the player missiles' nose-up convention (`homing_missile.gd:43`, `rotation = angle + PI/2`, with
  nose-up art), or rotate the trail child by PI. State which.

### 11. (minor) `score_value` as the threat weight; the plan's table is incomplete — t11
- **Plan:** `3-plan.md:621-623` lists fighter 25, ram 35, sniper 50, bomber 80, corvette 70.
- **Shipped values not listed:** gunship **200**, Gatling 75, razor 40, swarm 10 and bonus drone 500
  (`*_config.tres:9`).
- **Gunship:** the legacy gunship (`gunship.gd`, no brain or mover) becomes the preferred ward whenever it is on screen,
  and its escort can only ever time out (`accept_tow` false).
- **Bonus drones:** they are excluded only because `EnemyPathMover` suspends them (`enemy_path_mover.gd:70-71`); the
  plan does not say so.
- **Fix:** state the full weight table. Make an escort-incapable ward (no brain or mover) never trigger ESCORT. Name the
  bonus-drone exclusion explicitly, or move to a `support_priority` / threat config field (research §2.6's
  alternative).

### 12. (minor) The Warhead fairness inequality ignores the warhead's own motion — t6
- **Plan:** `3-plan.md:459-463`: the warhead "keeps moving" at up to 200 px/s through its 0.4 s warning, yet the Ph4
  mine rule `(trigger + blast) / warning ≥ 420` assumes a stationary blast centre.
- **Fix:** brake to a stop during the warning (mine-like, which makes the inequality exact), or put the warhead's
  velocity into the inequality and the t6 rows.

### 13. (minor) §13.2's "bubble projected by support ships" is deferred with a reason that does not cover it — t12
- **Plan:** `3-plan.md:121` and `:999-1000` defer shipped bubbles to "Ph11 fortress shield nodes".
- **IDEAS:** §13.2 ties the bubble to **support ships**, which this phase ships, and `EnemyShield` already supports 360°.
- **Fix:** either ship it (e.g. the projection becomes a bubble during ESCORT, when the support interposes), or record
  why the support projects only a directional arc.

### 14. (minor) Some `planSections` are missing sections the task needs — t15, t16, t17
- **t16:** the "hub support selects the Ram as its ward" row uses ward selection and `is_supporting()` from §2.12. t16
  lists only 2.17 and 2.16.
- **t17:** the support's attack-in-budget row uses `is_supporting()` (§2.12). t17 lists 2.18, 2.9, 2.10, 2.11, 2.13.
- **t15:** "RETURNING never interrupts TELEGRAPH or SALVO" and the escort's interplay with RETURNING are defined in
  §2.10 and §2.14. t15 lists 2.16, 2.9, 2.11.
- **Fix:** add 2.12 to t16 and t17, and 2.10 and 2.14 to t15.

### 15. (minor) Small internal inconsistencies to settle before t7/t8
- **Who sets `arm_distance`:** `fire()` sets `arm_distance` 52 (`:506`), while §2.6 says the launcher passes only
  "direction, aim point and itself" (`:374`). Pick one.
- **Warhead salvo count:** the Warhead salvo is a pair (`:545`) but the only count field is `salvo_count` 3. Add
  `warhead_salvo_count` 2, or say the pair uses the first two of `salvo_count`, so the t8 "exactly `salvo_count`
  rockets" row is unambiguous per kind.

---

## Checked and fine (no finding)
- **Layers:** a HitBox on `32 | 256` reaches enemy hurtboxes (runtime mask 1121), ordnance and plate hurtboxes (96) and
  asteroids (32), plus the player and ally hurtboxes (1281). `test_collision_layer_names.gd` needs no new name.
- **Single writer:** `accept_tow` → `add_nudge` and the brains' `projector.scale` writes are outside the gate's patterns
  (`test_enemy_mover_single_writer.gd:17-25`). The rocket is not a mover-driven root.
- **Hit flash:** decrease-only flash keeps `test_base_enemy_debt.gd`'s verbose-guard regex satisfied. The station's
  override (`space_station.gd:197-199`) still calls `super`.
- **Pools:** pool sizes 3/6/3/6 follow from the stated formula. `BulletPool` handover (`bullet_pool.gd:136-161`)
  supports pooled cluster parents splitting into self-owned children.
- **Density pin:** the specialist count gate filters by `_KIND_NAMES` (`test_level1_specialist_spawns.gd:120-136`). The
  plan's separate `EXPECTED_PH5` pin and the restated 50 + n line count are the right shape.
- **Task shape:** decomposition, ordering and complexities are reasonable. t2, t5, t8, t11 and t17 are large and get
  their own plans. t7 → t10 is serialised for the shared roster files.

---

# Round 2 (2026-10-15)

VERDICT: APPROVED

Reviewed `3-plan.md` Revision 2 (commit `fba9dd8`, §9 "Response to feedback"), `tasks.json`, `1-context.md`,
`2-research.md` and the Phase 5 section that commit added to `DECISIONS.md`. I checked each claim against the code at
`fba9dd8` rather than the plan's own summaries. All 15 round-1 findings are resolved. The fixes match the code, not just
the wording. I found no new blocking problem.

The eight new findings below are all minor. None needs a re-plan. However, the implementing agents see only `For every task`
plus each task's `planSections`, not this review. Findings 1–4 should therefore be folded into the named plan sections, or
into the task descriptions, when the epic is approved. Otherwise each will ship silently.

## Round-1 findings: resolution

| # | Round-1 finding | Status | Evidence (code checked) |
|---|---|---|---|
| 1 | Player missiles eaten by enemy rockets | **Resolved** | The player missile and bullet HitBoxes are 32 / 513 and 64 / 513 (`homing_missile.tscn:54-55`, `bullet.tscn:44-45`). The rocket's shoot-down HurtBox is now mask **96**, so it sees both. It is resolved in the rocket's own `area_entered` (`3-plan.md:441-446`), which ignores `EnemyRocket` HitBoxes, so sibling impact boxes on 32 are skipped. Mutual destruction, no blast. The t5 row asserts that **both** expire, so it can no longer pass on the old bug. `homing_missile.gd:51-54` frees itself on a non-deflecting hurtbox, as the plan expects. |
| 2 | Impact + blast impossible against i-frames; Warhead inverted | **Resolved** | The impact HitBox is on layer 32 only. The player and ally hurtboxes are mask 1281 (`player_ship.tscn:261-262`, `player_fighter.tscn:335-336`, `ally_fighter.tscn:42-43`), which lacks 32, so they never take the impact. Mask 128 still detonates the rocket on them. `ContactBlast` (256, `contact_blast.gd:35-41`) is the one source. The table is re-tuned so blast is the player number; the Warhead deals 30 either way. **Rows run on the real player scenes.** The `blast_radius + 20 → 0` row is sound: the player hurtbox radii are 5 × 2.2 = 11 px (OS) and 5 × 2.7 = 13.5 px (Assault), both < 20. |
| 3 | Launcher overruns its own rocket | **Resolved** | Launch speed now inherits the launcher's velocity along the launch direction (`launch_velocity()`). On a rail it is the observed position delta: `EnemyPathMover` writes `global_position` in `_physics_process` (`enemy_path_mover.gd:73-84`), so `velocity` is 0 there. Arming is by clearance from the launcher's **current** position. Every `cruise_speed ≥ 231`, and `launch_speed > 240 × boost_seconds` (all four check, `:494`). The HitBox mask also dropped bit 1, so rockets no longer detonate on enemy bodies. A moving-launcher row with a failing control and a railed-corvette HP row are added. Residual edge: new finding 7. |
| 4 | Tow drags a ward through its telegraph; brainless wards | **Resolved** | `EnemyBrain.accepts_tow()` is overridden in every shipped brain. I confirmed every phase name the plan lists exists in that brain's `enum Phase`, and that each brain has an `enter_phase()` (sniper `:51/:179`, ram `:51/:163`, bomber `:36/:175`, fighter `:60/:303`, gatling `:55/:186`, razor `:57-59/:229`, swarm `:59/:221`). `accept_tow` now requires `is_ai_driven()`, i.e. `_brain` and `_mover` present and not suspended. That matches the early return at `base_enemy.gd:103-108`. The nudge path really is per step: `enemy_mover.gd:190` sums `_primary + _nudge` and caps it; `:222` clears it. The control rows can fail: the sniper's `acceleration` is 520 and `lock_seconds` 0.5 (`sniper_config.gd:15,71`), about 65 px from rest, more than 50; the ram's is 500 over a 0.65 s WIND_UP, about 105 px. |
| 5 | Gate budget too small, unallocated, import/boot unmeasured, t3/t4 roots | **Resolved** | Import, boot and GUT are measured. There is a per-task allotment table (`:1246-1266`; it sums to 56.5 s and matches `For every task`). The ceiling is 240 s. t1 frees ≥ 70 s, with the slow files and the expected yield of each named. `tasks.json` t2–t5 now depend on t1 and every other task depends on it transitively. Owner question 4 is put up front. The yields are plausible: three files awaiting real physics at 1× (25.6 + 18.6 + 9.4 s; `test_ram_corvette.gd` has 55 awaits and no clock scaling today), plus moving fire-density from 4× to 8×, already about 70 s before `test_fighter_squad.gd`. ESCALATE is the fallback. Residual: new finding 6. |
| 6 | One rocket cannot break a 50 HP plate | **Resolved** | `ArmorPlate._resolve` applies `hit_box.damage` for ROCKET and breaks only at 0 (`armor_plate.gd:95-100,131-140`). The row is now 50 → 34 with no `plate_broken`, plus a weakened-plate break. The rocket asks `ArmorQuery` on the hull first, and `ram_corvette.gd:88-89` answers true, so the rocket flies through to the plate. Owner question 1 now says "about four". |
| 7 | `get_screen_center_position()` stale | **Resolved** | The plan now uses `global_position + offset` (the class doc at `arena_camera.gd:4-15`) and `viewport / zoom`, read in the same frame. `ArenaCamera` joins `assault_arena` unconditionally (`arena_camera.gd:78`). `EnemyWorld` is the single duck-typed lookup (`enemy_world.gd:19-50`), so `has_view_rect` / `view_rect` follow an existing pattern exactly. |
| 8 | Two corvette rows could not pass | **Resolved** | The chase is bounded: 2 s at 200 px/s, closest approach ≥ 228 px, back outside within 3 s. Arcing is measured as cumulative \|Δbearing\|. My estimate: Assault starts at R = 460, the radial escape reaches about 130–150 px/s at accel 240, giving about 270–310 px at t = 2 s. This passes **if the run starts with the drift near 0**. Started at the drift's −80 px extreme, it lands near the 228 bound. The t8 author should pin the seed / start so the drift is near 0, and not loosen the bound. The OS arc row gets 0.22 rad/s × 10 s ≈ 126°, comfortably above 60°. |
| 9 | Projected shield drains on an armoured Ram | **Resolved** | `absorbs_hit` is false while the host answers `is_armored()` (`ram_corvette.gd:82-83`). It never calls `deflects_hit`, correctly: on a plate that resolves and damages it (`armor_plate.gd:95-100`). The t2 counting-fake row and the t12 real-Ram row both prove this. Residual readability point: new finding 5. |
| 10 | Trail out of the nose | **Resolved** | Rockets are now nose-up, `rotation = heading.angle() + PI/2`, matching `homing_missile.gd:43-44`. `RocketTrail` emits along local +Y (`rocket_trail.gd:12-13,31-32`). t9 adds a "trail behind the nose" row. |
| 11 | Threat-weight table incomplete; gunship / bonus drone | **Resolved** | The full table matches every `score_value` in the `*_config.tres` files (gunship 200, bonus 500, station 1000, swarm 10, gatling 75, razor 40, …). `is_ai_driven()` excludes the gunship, station and bonus drone. `counts_toward_wave_clear` (`bonus_drone_config.tres:10` false, propagated at `base_enemy.gd:96-99`) excludes the bonus drone explicitly. `ward_min_score` 20 excludes swarm drones. There is a boundary row with a real gunship and a real bonus drone. |
| 12 | Warhead moves during its warning | **Resolved** | The Warhead now stops dead on trigger, so the Ph4 mine rule is exact, and a < 0.5 px row checks it. This matches the mine precedent: 30 damage, and a rule built to catch crossers (`mine.tscn:24`, DECISIONS Ph4 B1a). |
| 13 | Bubble deferred without a covering reason | **Resolved** | The projected arc widens to 360° during ESCORT and reverts afterwards, with a t13 row covering both. R5.30, §6 and §7 have been updated. |
| 14 | Missing `planSections` | **Resolved** | t15 now lists 2.10 and 2.14; t16 and t17 list 2.12 (t17 also 2.13); every test-adding task lists 4.3. I checked every `planSections` string against the headings: all exist, including "6. Requirements coverage" and "7. Out of scope". For each task, the listed sections are enough to build it. |
| 15 | Two owners of arming; Warhead salvo count | **Resolved** | The rocket alone owns arming (`arm_clearance` plus the launcher's `rocket_clear_radius()`), and `fire()` sets no rocket field. `warhead_salvo_count` 2 and `salvo_size(kind)` are added. `pool_size_for` gives 3/6/3/4, which I recomputed from the lifetimes. The pools prewarm disabled children, and `CollisionObject2D` removes those from physics (`bullet_pool.gd:66-75`), so idle rockets cannot collide. |

**15 of 15 resolved.** Residual edges of 3, 5 and 9 are filed as new minors 7, 6 and 5.

## New findings (all minor)

### 1. (minor) Ally fighters' contact HitBox on layer 64 silently "shoots down" enemy rockets — t5
- **Code:** `AllyFighter`'s `ContactHitBox` is on **layer 64** (`assault/scenes/allies/ally_fighter/ally_fighter.tscn:56-58`). The rocket's shoot-down HurtBox masks 96. The plan rule is that "any other `HitBox` defuses the rocket: small pop, **no blast**" (`3-plan.md:445`).
- **Where it happens:** level 1's deep_space spawns allies (`level_1_director.gd:327, 344, 438-439`, inside `_build_section_1` `:261-483`). That is exactly where t17 places a corvette.
- **Effect:** a rocket meeting an ally hits two things at once, its impact HitBox reaching the ally's hurtbox (128) and its HurtBox reaching the ally's ContactHitBox (64). Godot orders those two callbacks undefined, so the outcome is a coin flip between a blast and a harmless pop. The plan's "Player, allies … `blast_damage` only" row (`:422`) is false for allies half the time. No test covers allies.
- **Fix:** the shoot-down handler defuses only on a **projectile** HitBox. Concretely: ignore a `HitBox` whose parent is a `CharacterBody2D` (every contact hitbox's owner), or ignore any area named `ContactHitBox`. Add a t5 row: a real `ally_fighter.tscn` on the rocket's path takes exactly `blast_damage`. Put the rule in §2.6 *Shoot-down*.

### 2. (minor) The Assault halves of the dodge and Warhead-escape rows use stub speeds the Assault player does not have — t5, t6
- **Plan:** `3-plan.md:535-537` (a 420 px/s straight runner; a 700 px/s perpendicular boost), `:594` ("a 700 px/s boost escapes"), `:609`. All are marked "(both)".
- **Code:** the base Assault fighter moves at **360 px/s** (`assault/scenes/player/states/move_state.gd:20`) and dashes at 350 (`dash_state.gd:24`). A 700+ px/s escape in Assault exists only with the unlockable engine-boost module (1500 → 500 px/s, invincible; `engine_boost_module.gd:11-13`).
- **Effect:** with scripted, unconstrained stubs, the Assault rows pass but prove nothing about Assault. A 6 s straight run is also impossible inside the 1480 px corridor. With the base kit a triggered Warhead cannot be escaped in Assault (360 × 0.4 = 144 < 180). That is acceptable under the Ph4 mine precedent, but the plan should say it, not claim the opposite.
- **Fix:** read each stub's speeds from the real player of that mode (OS `player_ship.gd` `max_speed` / `boost_exit_speed`; Assault `move_state.gd` `move_speed`). In Assault, the PURSUIT dodge row becomes a 360 px/s sidestep. The Warhead row becomes "a stub that never enters `trigger_radius` is never triggered", plus "a boost-module stub escapes". State in §2.8 that the base-kit Assault counterplay is to keep out of the trigger radius or shoot the warhead.

### 3. (minor) In Assault the corvette can telegraph and launch from outside the visible view — t8 (and t17)
- **Plan:** TELEGRAPH needs only the launch cone and `salvo_period` (`3-plan.md:696-699`). The §43 "Off-screen" answer is "corridor-limited" (`:1092`).
- **Geometry:** the camera keeps the player near view centre (`arena_camera.gd` follow with deadzone). The view is 720 px tall, so its half-height is 360. An Assault orbit at R = 460 ± 80 therefore puts the corvette above or below the view for roughly 40 % of its bearings. In that case the tube glow is unseen and the rockets enter at cruise speed, which undercuts R5.6 "visible launch". `view_rect()` is built in t4 for exactly this kind of question, but t8 neither depends on t4 nor lists §2.5.
- **Fix:** in §2.10 item 3, add for Assault: "a TELEGRAPH starts only while the corvette is inside `EnemyWorld.view_rect(tree).grow(−48)`". Add a t8 row with the corvette 100 px above the view and no salvo. Add t4 to t8's `dependsOn` and 2.5 to its `planSections`. t17's attack-in-budget rows then measure with the gate in place.

### 4. (minor) Cluster rockets are effectively unreachable in Assault — t8
- **Plan:** CLUSTER requires `distance ≥ cluster_min_range` = 700 (`3-plan.md:701`, §2.9 table). The Assault hold radius is `assault_preferred_range + range_drift` ≤ 540, and the distance can grow to 700 only during APPROACH, where no salvo starts.
- **Effect:** Assault ships only three of the four kinds. That may be acceptable, but it should be a decision, not an accident.
- **Fix:** either add `assault_cluster_min_range` (e.g. 420–500) with a t8 row that picks CLUSTER in Assault for a crossing stub at that range, or state in §2.10 and DECISIONS that Assault has no Cluster salvos.

### 5. (minor) The projected shield is drawn on an armoured Ram although it absorbs nothing — t2, t12
- **Plan:** the shield refuses every hit while the host `is_armored()` (`3-plan.md:883-884`), but §2.3 *Drawing* (`:272`) draws the cyan arc by points fraction regardless.
- **Effect:** the player sees a cyan shield on the Ram while the plates do the deflecting. They will read the plates' glance-off flash as the shield.
- **Fix:** while the host answers `is_armored()`, draw the arc dormant (dim dashed outline, no flare) or hide it. Add one t2 unit row (`is_drawn_active()` false on an armoured host).

### 6. (minor) Per-task GUT allotments of 0.5–2 s sit below run-to-run noise — every test-adding task
- **Plan and tasks:** `For every task` and §4.3 set allotments as small as 0.5 s (t4, t9, t14) and 2 s. The acceptance criteria say "GUT delta within N s".
- **Problem:** whole-suite GUT time on a ~180–240 s run varies by more than that between identical runs. `scripts/gate-time.sh` prints only the 15 slowest files, so a small new file's own cost is invisible.
- **Fix:** gate-time.sh also prints every file's junit time, or at least those of the files the task changed (`git diff --name-only`). A task's allotment is checked against **its own files'** time. The whole-suite number is used only for the 240 s ceiling.

### 7. (minor) A rail faster than a rocket's cruise speed would still let the corvette overrun its armed rocket — t7
- **Plan:** the inequality bounds the launcher's **AI** `max_speed` (`3-plan.md:461`). On a rail, launch speed is `launch_speed + rail speed`, and then `move_toward(cruise_speed)`.
- **Example:** a `straight(300)` rail is 600 px/s, above DUMB's 520 cruise. The rocket decelerates below the ship's speed after arming, and the corvette catches it.
- **Scope:** nothing places a corvette on a rail today (§2.9), so this is latent.
- **Fix:** the rocket never decelerates below its inherited along-heading speed plus a margin (`target = max(cruise_speed, inherited × 1.1)`). Alternatively, the rail fallback fires sideways. State it in §2.6.

### 8. (minor) Note for t8: pin the drift phase in the bounded-chase row
- See round-1 finding 8 above. In Assault the ≥ 228 px bound holds when the run starts with the range drift near 0. Started at −80 px it is marginal.
- **Fix:** the row seeds the brain (or starts the stub at a drift zero-crossing) so the result is deterministic. It never loosens the bound.

## Checked and fine (no finding)
- **Layers:** every target that should take rocket impact has a hurtbox on 512 that masks 32: enemy hurtboxes (runtime 1121), plates (`ram_corvette.tscn:123-125`), ordnance (`mine.tscn:29-31`), big and small asteroids (`big_asteroid.tscn:35-37`, `small_asteroid.tscn:37-39`). Mask 128 | 512 detonates on all of them and on the player, with no bit 1. Enemy contact hitboxes are on 256 (`bomber.tscn:95-97`), outside the rocket's shoot-down mask 96. Open Space has no asteroids, so "hits the environment" is Assault-only, which is consistent.
- **Shield hook:** the bullet decides through `ArmorQuery` (`bullet.gd:125-139`) and the hurtbox decides through its absorber, both per hit and consistent. An absorbed hit is not deflected, so it consumes the bullet and spends a pierce charge. The Sniper Shot path (`bullet.gd:110-121`) still passes on. The beam picks targets from `enemies` (`beam_behavior.gd:87-113`), so rockets are untouched by it, and the plan already defers that question to Ph8.
- **Repair:** `Health.increase` (`health_component.gd:30-32`) emits through `set_health`. `ContactProfile._on_health_changed` acts only at 0 (`contact_profile.gd:151-153`). The overrides of `_on_health_changed` in shipped enemies are `space_station.gd:197` (calls `super`) and the gunship's own handler (not a ward), so decrease-only flash is safe.
- **EMP:** `emp_blast_module.gd:59-66` sets the enemy's `process_mode` to DISABLED. That freezes the support's sustain calls, as the plan assumes. Rockets are not in `enemies` and are unaffected.
- **Hub:** 12 seeded draws today (4 swarm + 1 razor + 2 + 2 + sniper, bomber, ram; `sector_hub.gd:56-69`). The corvette anchor (1343.5, −1343.5) and the Ram anchor (−1202, −1202) are as stated. The nearest other patrol anchor to the Ram's is the Razor's at about 1206 px, beyond `ward_search_radius` 900, so "the support guards the Ram" holds until the player drags a higher-score group over.
- **Lifetime arithmetic:** I recomputed all five rows (DUMB 3.80, PURSUIT 5.90, CLUSTER 3.55, SUBMUNITION 1.15, WARHEAD 5.76); all are correct.
- **Task shape:** decomposition, complexities (t2, t5, t8, t11, t17 large), dependencies and the critical path are sound. t7 → t10 is serialised for the roster files. t15 waits for both brains, and t17 for t15. No two parallel-eligible tasks edit the same file.
