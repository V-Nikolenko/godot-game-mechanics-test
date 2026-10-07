VERDICT: CHANGES_REQUESTED

# Review: Enemy rework, phase 4 (Bomber, Sniper, Ram Corvette), plan Revision 1 and tasks.json

Reviewer: independent plan review, round 1, 2026-10-07. Read: `1-context.md`, `2-research.md`, `3-plan.md`,
`tasks.json`, CLAUDE.md, `tests/README.md`, DECISIONS.md (all three phases' *as built* sections and the Ph4 planned
section), the Ph1–Ph3 REPORTs, and the IDEAS sections the scope names (§3.2, §5.5–5.7, §12, §13.1, §16, §21–23, §28, §31,
§38, §40, §41). I checked the code the plan relies on.

## What holds up (checked against the code, no action needed)

- **Armour design (A3, X3, X7) is correct and minimal.** A bullet's `HitBox` (layer 64, mask 513) detects any area on
  512 whatever that area's own mask is (`bullet.tscn:44-45`, `homing_missile.tscn:54-58`, `warhead_missile.tscn:60-64`).
  `_hit_is_deflected` is duck-typed `is_armored()` in all three projectiles (`bullet.gd:131-133`,
  `homing_missile.gd:55-58`, `warhead_missile.gd:31-35`). `HurtBox.received_damage(damage: int)` carries no type
  (`hurtbox_component.gd:4,18`). So a hit-aware `deflects_hit(hit_box)` is the smallest way to say "deflect a bullet,
  accept a rocket". The station implements neither new method, and keeping it byte-identical, gated by its suites
  passing unedited, is the right acceptance.
- **The homing "parks in the hull" claim is real.** `homing_missile.gd:37-40` steers at `locked_target.global_position`
  with an instant turn. `homing_point()` is a justified additive hook.
- **`BulletPool` facts are right.** There is an anonymous lambda per bullet (`bullet_pool.gd:59`), `_exit_tree →
  cancel_active` (`:115-116`), and `_recycle` already guards `_idle.has` (`:83`). P1 matches the Ph1-designed shape.
  Pulling it into Ph4 is declared (X1) and fits the scope, which names §12.
- **The old Ram uses layer immunity.** It has a scene `DefenseProfile` with mask 33, `apply_alternate()`, HP 999, the
  group `ram_ships` only, and a straight `_physics_process` dive (`ram_ship.gd`, `ram_ship.tscn:76-90`). The
  `_IMMUNE_CLASSES` lists match by global class name (`emp_blast_module.gd:9,55`, `engine_boost_module.gd:19,154`), so
  the rename must touch both lists. t7 says so.
- **Level-1 counts are 26 / 22 / 2.** cloud_descent has 9 snipers and 6 rams. The last trigger is 76.0 s and the ram
  enters at 72.0 + 1.2 s (`level_1_director.gd:809-1001`). `sniper_enemy()` is an alias of `SNIPER`
  (`wave_builder.gd:90,252-253`). The `FLY_IN_TIME` coupling is as described (`sniper_enemy.gd:24-25,60-65`).
- **The `TargetInfo.line_of_sight` stub and its only callers are as described** (`target_info.gd:117-118`,
  `test_target_info.gd:129-132`).
- **The renames are justified.** They use the IDEAS names and follow the Ph2/Ph3 `git mv` precedent, and the blast
  radius in `1-context.md` is essentially complete (my grep of `assault/ global/ open_space/ tests/` matches it).
- **The Ph7 and Ph16 boundaries are drawn sensibly.** Ph7: one proximity mine kind in a new `enemy_ordnance` family
  that Ph7 extends. Ph16: `decoy_telegraph` is a plain config bool, CHARGING-only, never COMMIT.
- **The research has real tradeoffs per approach (A1–A4, P1/P2, L1–L3) and its sources support the claims they are
  cited for.**

## Findings

### 1. BLOCKING: The Bomber's prediction is on the wrong time base, and the placement test cannot detect it (R4.5) (t10)

`3-plan.md:258-279` defines `P̂ = P + v̄ · 0.6 · min(1.2, d / run_speed)`, with `d` the bomber–player distance. It never
says when the line is fixed. As written, the line is chosen at APPROACH start, and a `DubinsPath` lead-in capped at 6 s
then flies to it.

**For a constant-velocity player, the mine wall always lands behind the player:**
- At the plan's own test speed (220 px/s), the player moves 220 px for every second of approach, against a lead of at
  most 158 px. A line frozen at APPROACH start is hundreds of px behind the player by the time RUN starts.
- Re-planning until RUN entry does not fix it. The bomber reaches the line centre about 1.06 s into RUN
  (180 px / 170 px/s). By then the player has moved about 233 px, past a P̂ that was 158 px ahead. The mines also arm
  another 0.5 s later.
- F9's damping (factor 0.6) is a rule for **aimed shots**. Applied to a persistent wall, it guarantees the wall is laid
  where the player has already been.

**The R4.40 placement test cannot catch this** (`3-plan.md:690`):
- It measures mines against `P̂`, which holds by construction.
- "Centroid ≥ 100 px closer to P̂ than to the player at drop time" passes most easily exactly when the mines are far
  behind the player.

R4.5 ("drops a mine chain **ahead of** the player's current trajectory") can therefore ship broken with every gate
green.

**Resolve:**
- (a) State that the line is (re)planned from a fresh prediction until RUN entry and frozen there, with the Dubins
  endpoint re-planned as it moves.
- (b) Base the MINE lead time on the bomber's own timeline: time to the drop point plus `mine_arm_delay`, clamped by
  the horizon. Use a lead factor of about 1 for walls, and keep the damped lead for the gravity bomb and pursuit aim
  point. Say why a wall ahead is still fair: a committed turn escapes it.
- (c) Keep the P̂ assertion, and **add a live-player assertion** in both harnesses. At each mine's arm time, the mine's
  projection on `v̄` relative to the live player is > 0 (ahead), and the player's straight-line path passes within
  `trigger_radius` of at least one armed mine. The current assertion should fail on the Revision 1 design.

### 2. BLOCKING: The Ram's deadline deferral leaves out LINE_UP, and `charge_max_time` is never defined (t17, t22)

`3-plan.md:471` defers budget expiry "in LINE_UP, WIND_UP or CHARGE … (deferral ≤ 0.65 + `charge_max_time` 1.2 s)".
`3-plan.md:559-564` and t22's description build the 73.2 s ram row on that 1.85 s. Two problems:

- **LINE_UP has no time bound.** It turns at `max_turn_rate` 2.2 rad/s "until the nose is within 8° of the intercept
  line" (`:445`), against a moving line. A half turn alone is π/2.2 ≈ 1.43 s. An expiry at LINE_UP entry therefore
  defers up to about 1.43 + 0.65 + CHARGE, not 1.85 s. On the plan's own figures the 73.2 s row becomes
  4.5 + 3.28 + 4.55 = 12.33 against an allowed 12.3. The tight row fails, or worse, passes on paper while the real ram
  overruns. This is the Ph3 deviation-18 failure mode the plan cites.
- **`charge_max_time` appears only in the deferral.** CHARGE's boost duration is `(|P̂ − pos| + overshoot) / charge_speed`
  (`:454`). With `engage_range` 420, a lead of up to 0.6 s × player speed, and a 220 px overshoot, that exceeds 1.2 s
  (about 890 / 620 ≈ 1.44 s).

**Resolve.** Either:
- do **not** defer on expiry during LINE_UP (go straight to the nearest-edge exit, so only WIND_UP + CHARGE defer); or
- add a `line_up_cap` config field and put it in the deferral.

Also define `charge_max_time` as a hard cap on the boost duration in §2.6.2. Write the deferral formula from config
fields in t22 (`wind_up_seconds + charge_max_time [+ line_up_cap]`), and add a boundary row: a ram whose budget expires
on its first LINE_UP tick still exits within the computed bound. The arithmetic at `:563` also double-counts the 0.5 s
margin. The allowed 12.3 already excludes it, so the real slack is 1.4 s, not 0.9 s. That does not change the verdict,
but the printed figure should be right.

### 3. BLOCKING: Nothing checks that a level-1 specialist can attack inside its Assault budget, and the Ram probably cannot (t17, t21, t22)

`EngagementBudget` counts from spawn (`engagement_budget.gd:37-47`). The plan asserts "4.5 s = one charge"
(`3-plan.md:470`), "9.0 s = one or two shots" and "8 s = one run", but no task computes or tests this from the real
level-1 spawn offsets.

For the Ram it looks false for most spawns:
- 16 of the 22 rams spawn at y = −400 design units, 800 px above the camera centre
  (`level_1_director.gd:341,453,610,634-636,…`).
- The new `cruise_speed` is 160 px/s. Fighters cruise at 300 (`fighter_config.tres:10`), and the legacy rams moved at
  520–700.
- To get within `engage_range` (420) of a player in the lower half, with the 240 px `assault_side_offset` added, the
  ram covers about 600+ px at 160 px/s (about 3.7 s). LINE_UP and the 0.65 s WIND_UP then push the charge to about the
  4.5 s expiry.
- Expiry in APPROACH exits at once (`:475`), with no charge.
- The pre-approved levers (`:546-549`: ram 4.5 → 3.5; `:565`: → 4.0) make it strictly worse.

The likely result is that level-1 rams drift in and leave without attacking. The bomber is marginal too: a Dubins
approach capped at 6 s plus a 2.1 s RUN, against an 8 s budget, from 800 px above the screen. No gate would notice,
because the deadline and count gates only bound lifetime.

**Resolve:**
- Add a row per enemy, in t17 / t13 / t10 or in t21, run through the real `WaveManager`/harness. From each level-1
  spawn-offset class (top, bottom, side) against a stub in the lower corridor, the enemy reaches its attack state
  (CHARGE / FIRE / RUN) before its budget expires.
- Size the Ram's Assault approach so the row passes, either with an Assault approach speed or by counting the budget
  from corridor entry. Record the measured "attacks per life" the way Ph3 recorded "one burst per life".
- Re-examine levers that shorten the ram budget, since they trade density for a ram that never charges.

### 4. BLOCKING: The ordnance lifetimes fail the plan's own round-lifetime sweep (t6)

The sweep's rule is `max_distance / slowest fired speed ≤ max_time` (`test_enemy_bullet_lifetime.gd:164-166`), and the
plan extends it to "moving kinds" (`3-plan.md:244-246,687`). Its own values break it:

- **Gravity bomb:** 1800 px / 120 px/s = **15 s > 12 s** (`:235`). It fails exactly like the plan's synthetic boundary
  row.
- **Pursuit bomb:** the "slowest config speed" is the 90 px/s launch (`:237`), so 2400 / 90 = 26.7 s > 10 s. The kind
  only travels at 90 for the 1.5 s steer window, so the formula does not even model it.

An unattended sonnet run that meets a red row tends to loosen the sweep rather than the data.

**Resolve:**
- Gravity bomb: pick consistent caps, e.g. 16 s / 1800 px, or 12 s / 1400 px.
- Pursuit bomb: give the row a kind-specific travel-time bound, `steer_window + (max_distance − launch_speed ×
  steer_window) / final_speed` ≈ 7.5 s ≤ 10 s, read from `BomberConfig` fields.
- Say explicitly that ordnance speeds go into the **per-round** sweep, never into `_every_shipped_enemy_bullet_speed()`
  (`:63-117`). The 120 / 90 px/s values would trip `test_every_shipped_speed_source_is_at_or_above_150` and shift the
  derived 18 s / 2400 px defaults.

### 5. BLOCKING: Two parts of the requirements are narrowed without being listed (R4.31, R4.37 / §16) (t16, t5)

- **IDEAS §5.7:** "Each plate can be damaged independently by **rockets or high-impact weapons**." The plan makes plates
  `ROCKET`-only (`3-plan.md:188,194`). The coverage table (`:753`) reads "R4.31 … rockets break them", with no note that
  "high-impact weapons" was dropped. `deflects_hit(hit_box)` could easily allow the player's sniper shot (or
  `hit_box.damage ≥ threshold`) to hit a plate. If the plan prefers rockets only, that is a legitimate design call, but
  it must be stated as a deliberate narrowing, with its reason, in §2.0 or §7 and in the owner questions.
- **IDEAS §16:** "Armor collision: deals high **stagger**/contact damage." `ContactProfile.ARMOR` (`:477-489`) deals
  plain contact damage only. A player shove already exists: `PlayerBase.apply_knockback(impulse)`
  (`global/entities/player_base.gd:132`). Note that it is only *applied* by `player_fighter.gd:76`, so the Open Space
  ship would need `apply_knockback_motion` too. The plan should either use it (ARMOR's `contact_made` → shove the
  player) or list "player stagger from armour contact" as deferred, with the phase and the reason.

**Resolve:** for each item, either build it in t16 / t5 (and add a test row), or add it to §6 / §7 as an explicit
deviation with its reason.

### 6. BLOCKING: The hub `lose_radius` is unspecified, and the Sniper's core loop deliberately exceeds a fighter-like one (t19)

`AnchorIdle` drops COMBAT → RETURNING whenever the **actor–player** distance exceeds `lose_radius`
(`anchor_idle.gd:62-64,78-79`). Phase 3 used 900 for fighters and Gatlings (`fighter_config.tres:51`,
`gatling_interceptor_config.tres:39`).

- The Sniper's design in Open Space is to break contact to `0.9 × preferred_range` and then relocate to
  900 ± 100 px (`3-plan.md:320,326-327`).
- With any `lose_radius` ≤ about 1100, it goes RETURNING in the middle of BREAK_CONTACT / RELOCATE. Those are states
  the plan does not protect: it only lists RUN / AIM-LOCK / CHARGE (`:580`). It flies home, re-notices at 700, and
  repeats.
- The Bomber's ESCAPE (200 px/s for 1.6 s) plus its 520 px standoff has the same exposure.
- §2.10 gives perceive radii only. t19's tests check "RETURNING beyond `lose_radius`" (`:696`), which this defect
  passes.

**Resolve:** in §2.10, set `lose_radius` per enemy above the largest distance its own behaviour deliberately opens:
- Sniper: ≥ `preferred_range + range_jitter + margin`, about 1300.
- Bomber: ≥ standoff plus the escape distance.

Add a t19 row in which a hub sniper that runs a full BREAK_CONTACT → RELOCATE → FIRE cycle against a stationary player
stays in COMBAT throughout.

### 7. BLOCKING: Missing dependencies let tasks collide on the same files (`tasks.json`)

The plan serialises t9 → t12 → t16 to protect `test_enemy_dual_mode.gd`, so it assumes tasks may run concurrently.
Under that assumption, these unordered pairs edit the same files:

- **`t6-ordnance` ∥ `t8-rename-sniper`** (`tasks.json:55-57` vs `:79-82`). Both edit `test_enemy_bullet_lifetime.gd`:
  t6 adds the ordnance rows, and t8 renames `SNIPER_ENEMY_SCENE` / `SniperEnemy` at `:17,278-310`.
- **`t14-sniper-decoy` ∥ `t19-specialist-idle`** (`:151-153` vs `:209-213`). Both edit `sniper_brain.gd`,
  `test_sniper.gd` and `SniperConfig`.
- **Art against behaviour on the same `.tscn`.** These are hard to merge:
  - `t11-art-bomber` (depends only on t9) ∥ `t10-bomber-runs`;
  - `t15-art-sniper` (depends only on t12, and moves the `Muzzle` marker) ∥ `t13`/`t14`;
  - `t18-art-ram` (depends only on t16) ∥ `t17-ram-charge`, which wires plate glow on the same plate nodes.

  Phase 3 ordered its art tasks after the behaviour tasks (`cmufs7ekv000lnm2x7nbswijy/tasks.json`: t14-art-fighter →
  t9, t15-art-gatling → t11).

**Resolve:** add `t8 → t6` (or `t6 → t8`), `t19 → t14`, `t11 → t10`, `t15 → t14` and `t18 → t17`. None of these
lengthens the critical path, which runs through t17 → t21 → t22.

### 8. NON-BLOCKING: Rocket volleys and the Assault time-to-kill are not examined (t16, §8)

The player fires rockets in **volleys of three** on a 5 s cooldown (`warhead_missile_shooting_state.gd:56-77`;
`CooldownTimer wait_time = 5.0` in both player scenes).

- **Homing volley.** With `homing_point()` re-targeting the *nearest live* plate every frame, one homing volley
  against a lone Corvette can plausibly strip all three plates (rockets two and three re-aim once the first plate is
  freed).
- **Warhead volley.** A frontal warhead spread (±16 px) probably breaks only the front plate. Exposing the hull then
  takes three volleys (≥ 10 s), longer than the Ram's 4.5 s Assault life. Level-1 rams become effectively unkillable
  with warheads and trivially stripped with homing rockets.

"Plate HP 50: one rocket breaks one plate" (`3-plan.md:428`) assumes single rockets. Suggested resolution:
- add a t16 row firing a real `_launch_homing()` volley at a lone Corvette, and state how many plates it may strip;
- put the Assault time-to-kill against the budget into owner question §8.6, with numbers.

### 9. NON-BLOCKING: `RailTrail`'s weak reference cannot see a pooled recycle (t13)

`3-plan.md:355-357` relies on "a weak reference to the round, so a recycled round is never read". A pooled round is
not freed when it expires: `_recycle` reparents it into the pool and hides it (`bullet_pool.gd:86-91`), so the
`weakref` stays valid and the trail would follow a parked round. The trail should connect one-shot to the round's
`expired`, and keep the `weakref` only for the owner-death `cancel_active()` free.

### 10. NON-BLOCKING: `beam_behavior.gd` has no "excluded-and-recast loop" (t2)

`3-plan.md:136-138` and `2-research.md` §2.4 say LOS copies "`beam_behavior`'s excluded-and-recast loop". The beam
casts **one** ray. A non-blocking first hit makes the whole beam unblocked (`beam_behavior.gd:58-71`), and nothing is
recast. The capped recast loop is therefore new code with no precedent to copy. Fix the wording so the t2 implementer
does not go looking for it. The design itself is fine.

### 11. NON-BLOCKING: The rename acceptance criteria are inconsistent with the assets (t7, t8, t18)

- **t7.** Its acceptance (`tasks.json:72`) is "No reference to ram_ship/ or RamShip remains outside docs history". The
  hull texture stays `ram_ship.png` until t18 (`ram_ship.tscn:4`, `ram_ship.gd:37` loads `ram_ship_damaged.png`), and
  t18 deletes "`ram_ship.png` … if nothing references them". Say whether t7 renames the PNGs (with `git mv` of the
  `.import` files) or the criterion excludes asset paths.
- **t8.** It must edit the `SniperEnemy` comment in `sniper_aim_visualizer.gd:52`, while t12's acceptance says
  `SniperAimVisualizer` is unchanged. Scope that to "behaviour unchanged".

### 12. NON-BLOCKING: `test_base_enemy.gd` characterization cases are not named in t12 / t16

- **t16** must retire or rewrite the ram-specific cases: `_RAM_MASK_BEFORE_HIT` (`:122`), `_RAM_SHIP_SCENE`,
  `test_ram_ship_hurtbox_mask_flips…` (`:156`), `test_ram_ships_first_hit_only_arms…` (`:233`) and
  `test_ram_ship_dies_on_a_lethal_hit_after_being_armed` (`:253`). It must also keep the Corvette in
  `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW` (`:71`), because its hull deflects like the station's.
- **t12** must update `test_sniper_enemy_hardcodes_its_score_value` (`:296`) and the `_MIN_ROSTER_SIZE - 1` "sniper is
  the exception" sweep (`:279-290`), since the sniper gains a config.

List these so the implementer edits them deliberately rather than "making red go green".

### 13. NON-BLOCKING: Gaps in the count gate and the replay (t21, t22)

- **Exit model.** §2.9.2's lifetimes ("`ai_shooter_kinds()`-style … `entry + engage + deferral + exit`") must use the
  curved or measured exit for the sniper and bomber. Ph3's open item (DECISIONS Ph3 as built, "Open items") records
  that the straight-line exit under-reported the fighter's life by about 2.5 s and moved a count gate from 18 to 21
  against 20.
- **cloud_descent count gate.** t22 should also apply the count gate to cloud_descent and retire that section's
  live-equals-constant check, as Ph3 t17 did. The plan only describes the DURATION sections.
- **Replay window.** `test_level1_specialist_exit.gd` must start at or before 62.0 s. `test_level1_fighter_exit.gd`
  starts at 66.0 s (`:39`), so it excludes the 63.2 s snipers, which are cloud_descent's latest sniper entries.

### 14. NON-BLOCKING: The Bomber's body shape against a wide silhouette (t9, t11)

A `CircleShape2D` body (`3-plan.md:250`) under a 104 × 56 sprite leaves about 24 px of each wingtip with no hurtbox.
The legacy bomber already has this: r 22 under 92 × 42. The hurtbox gate checks the body, not the sprite, so it will
not notice. Consider a capsule or rectangle body shared by the contact box and the hurtbox, sized to the "wide"
silhouette R4.1 asks for.

### 15. NON-BLOCKING: Smaller test-wording points

- **Post-shot disengage.** "Distance strictly increases over the 1.0 s after FIRE" (`3-plan.md:692`) starts from rest,
  so the first tick changes distance by about 0. Phrase it as non-decreasing per tick, and strictly greater at 0.25 s
  and 1.0 s.
- **Hub test counts.** `test_sector_hub_patrol.gd:255` asserts the container holds exactly the four groups, and
  `:340-370` lists the drones that must not perceive the player at frame 0. Both need the new groups (t20).
- **Race-mode mine.** `assault/scenes/race/track/mine.gd` already uses group `mines`. Worth a line in §7 for Ph7, so
  the two mine concepts are reconciled there rather than collide.
