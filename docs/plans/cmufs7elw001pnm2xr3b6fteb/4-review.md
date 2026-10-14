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
