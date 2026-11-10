VERDICT: CHANGES_REQUESTED

# Plan review — round 1 (task cmug23ool002nm52w3224nn13)

Two independent reviewer subagents read 3-plan.md, tasks.json, CLAUDE.md, DECISIONS.md and the referenced code: reviewer A (design against the code, §1–§2.10, §2.16) and reviewer B (task breakdown, planSections, gates, level 1, hub, §2.11–§7). Both returned **CHANGES_REQUESTED**. Merged verdict (strictest wins): **CHANGES_REQUESTED**. There is no 1-context.md or 2-research.md; the plan's §1.2 carries the research. Their merged findings come first, then each reviewer's full report.

## Merged findings

The overall design is sound and covers everything this phase asks for. The parts framework doesn't duplicate anything that exists, the Heavy Gunship and Carrier behaviours match the idea, and the hub placement checks out. The plan still needs another pass before anyone builds from it. In several places it assumes things the code doesn't do:
- Parts inside the Gunship's hull can never be hit.
- Enemy beams can't reach parts, and making them do so would let the Carrier's pulse ring damage its own parts.
- The Gunship's rear rockets outlive it and hold Cloud Descent open.
- A 14 s engagement budget can't meet Cloud Descent's 10 s timeout.
- The level-start laser wall is left out.
- The planned laser-column replay lights no columns, so it can't fail.
- The Carrier's column-free time window is computed from the wrong timings, the default placement has no safe x position, and its sideways sway, hazard avoidance and speed cap let it drift into columns anyway.
- Removing the old gunship breaks Level 2's compile.
- The transparency check never sees the wreck textures.
- Nothing tests a beam or nova against a part that should be immune.

I would send it back for a re-plan that fixes those eleven points and folds in the minor ones below. Each fix is local: no part of the design has to be rethought.

| # | Severity | Problem | Fix | Tasks |
|---|---|---|---|---|
| 1 | blocking | The Gunship's hull is vulnerable and covers the whole body, so a bullet or rocket is spent on the hull outline before it reaches any part inside. Inner parts, the vents and rocket homing onto a part never work, and the nose-cannon shield stops nothing. | Add a geometry rule: every part a shot must reach has a hurtbox that reaches the outline on its exposed side. Prove it with a real-physics row per part in both modes, and say the shield protects only the cannon's own HP. | t2, t4, t5, t9 |
| 2 | blocking | Enemy beams don't look for parts, so the planned "an enemy beam kills a part" row fails. Adding parts to the beam's targets would make the Carrier's pulse ring destroy its own parts. | Either drop the enemy-beam claim and keep the level laser, or exempt parts whose host is exempt and add a "ring never damages its own parts" row. | t2, t7 |
| 3 | blocking | The Gunship's rear rockets outlive their ship and hold Cloud Descent (an enemies-cleared section) open, against every earlier phase's rule, and the deadline ignores them. | Close the missile mount in Assault once the budget nears its end, or add the rocket flight time to the deadline. Add a boundary row and record the decision. | t5, t11 |
| 4 | blocking | Cloud Descent's late Gunship has to attack and leave within 23.2 s. A 14 s budget leaves 8.7 s, which is less than even the faster Missile Corvette needs to leave, and no lever is approved for it. | Derive the budget from the deadline (about 10–11 s), or pre-approve ordered levers, each legal only while the attack-in-budget row stays green. | t4, t11 |
| 5 | blocking | The level-start laser wall (x 0–672, lethal at about 3–7 s) is left out. The deep-space Gunship spawns inside it, and the plan's fallback position lands in it too. | Name the wall and add it to the column check, and change the fallback to +160 only. | t11 |
| 6 | blocking | The planned laser-column replay lights no columns, so its "no part killed" row cannot fail. | Light the section's columns (and the wall) in the replay, count part and hull deaths, and add a boundary row that proves a kill is detected. | t11 |
| 7 | blocking | The Carrier's column-free window was worked out from the wrong timings. The column warn and active times are director defaults, not laser exports. Its roughly 22 s crossing fits no gap between columns, and the default option has no safe x. | Read the real timings, check each column's lit window for overlap separately, put a feasible option first (one that also avoids the jammer at x 480), and stop reusing the existing conflict check unchanged. | t12 |
| 8 | blocking | In Assault the Carrier sways after the player across the whole view and its default hazard avoidance bends its "constant" descent. Its speed cap of 70 squeezes the descent to about 61 px/s, and EMP halts stretch its life. | Add a sway leash around the spawn x, set the Carrier's hazard profile explicitly, raise the Assault speed cap to about 81, and bound the life including EMP halts. Add a row with the player held at each view edge. | t6, t12 |
| 9 | blocking | Level 2 still calls the old gunship builder, so removing it breaks Level 2's compile and fails the project-load gate. One station test also names the old scene. | Have t4 move Level 2 to the heavy builder (rails kept), rename the station test assertion, and correct the scope note. | t4 |
| 10 | blocking | The transparency check walks only sprite textures, so wreck, door and core textures stored as exports are never checked. An opaque wreck would pass. | Extend the walk to texture-valued exports, or run the same check in the new sprite test, and put that in t9's acceptance criteria. | t9 |
| 11 | blocking | No row fires the beam or nova at a part that should be immune (closed vent, plated core, closed hangar). These weapons skip deflection, so this is the core-vulnerable-only-when-intended requirement. | Add beam and nova rows against those three parts to the framework fixture and to the Carrier rows. | t2, t6 |
| 12 | minor | Some tasks' plan sections miss what they need, and one cross-reference is wrong. | Add the missing sections and fix the cross-reference (detail below). | t5, t6, t7, t12 |
| 13 | minor | Framework details are missing or wrongly worded: | See the detail below for the fixes. | t2, t3 |
| 14 | minor | The Gunship must keep a started burst firing while it vents, its own rockets can hit its own parts, and the Carrier's open questions aren't answered. | Specify each (detail below). | t5, t6, t7 |
| 15 | minor | Some acceptance criteria and gate checks are incomplete. | Fix each (detail below). | t2, t4, t10, t11, t12 |
| 16 | minor | Gate-time allotments look mis-sized, the art can change geometry under the level-1 measurements, and one hub fallback bearing is unusable. | Rebalance the allotments, freeze t9's geometry or make t11 and t12 depend on t9, and drop the 22.5° fallback. | t2, t4, t9, t10, t11, t12 |
| 17 | minor | An earlier phase handed EMP on the bonus drone, the station and the Ph8 turrets and fences to phase 10 or 11, and this plan doesn't say which. | List it under out of scope (probably phase 11). | t13 |

### 1. The hull shields interior parts
`bullet.gd:117-140`, `hurtbox_component.gd:41-49` and `homing_missile.gd:273-300`:
- A projectile is spent on the first damaging overlap. That is the full-body hull hurtbox, at the outline, and the projectile is freed in the same frame.
- A part is therefore only hit if its hurtbox reaches the outline on the side the shot comes from.
- Rockets steered toward `homing_point` are eaten by the hull.
- The "open vent takes 2×" row passes only if the vent touches the outline.
- A head-on bullet still damages the hull through the overlapping root hurtbox, so the cannon shield stops nothing.

Fix:
- Add the rule that every hittable part's hurtbox reaches the outline on its exposed side by at least one bullet step (about 16 px).
- Add a real-physics row per part in both harnesses, fired from its exposed bearing, or pick a different hull rule and say why.
- Say in §2.5 that the cannon shield protects only the cannon's own HP.

### 2. Enemy beams and parts
- `energy_hit_scan.gd:17`: the beam's victim groups are player, allies, enemies and asteroids. They do not include `enemy_parts`.
- `energy_hit_scan.gd:37-42`: `is_exempt` checks only the host and the owner group.
- So the §2.1 row "an enemy `EnemyBeam` kills a module" fails.
- Adding the group to make that row pass makes `carrier_pulse_ring.tscn` sweep the Carrier's own parts.
- `LaserRay` already hits parts on layer 512 (`laser_ray.gd:81-127`).

### 3. The rear rockets persist in an enemies-cleared section
- `rocket_battery_mount.gd:42-53` creates the rocket pools with `persist: true`, and `test_level1_specialist_spawns.gd:1587` pins it.
- `level_director.gd:170` waits until the enemy container has no children at all.
- `pursuit_rocket.tscn:37` gives a rocket `max_time` 6 s.
- DECISIONS.md :1555, :1954 and :2940 keep persistent ordnance out of enemies-cleared sections. The plan breaks that without saying why.
- The Assault attack gate covers only the battery and cannon telegraphs.
- Fix: gate the missile window on the remaining budget (missile window + rocket `max_time`), or don't open the mount in Assault enemies-cleared use. Add a boundary row in the style of `test_a_corvette_in_cloud_descents_last_wave_misses_the_timeout_on_the_rocket_term_alone`.

### 4. The Cloud Descent deadline
- `test_engagement_deadline.gd:236-260` with `MARGIN 0.5` (:28): the 62.0 + 0.8 s heavy has a relative start of −13.2 s, so engage + attack window + exit + 0.5 must be at most 23.2 s.
- A 14 s budget leaves 8.7 s for the attack window and the exit.
- The Missile Corvette's measured corridor exit is already 8.72 s (DECISIONS.md:2138), and the corvette is faster than the heavy (280 / 240 / 1.2 against 260 / 120 / 0.9).
- §2.12's levers cover laser columns only.

### 5. The level-start laser wall
- `level_1.tscn:46` places a static 12-ray `LaserWallWave` over x 0–672, lethal roughly 3–7 s into deep_space. It is not part of `laser_column_schedule()`.
- DECISIONS.md:3421 says static things in deep_space must clear both the columns and the wall.
- The 3.5 s heavy at world x 640 has its 112 px hull inside the wall's span.
- The fallback `.at(-160, -500)` puts it at x 320, also inside the wall.
- Fix: reuse `_wall_wave_row()`.

### 6. The column replay cannot fail
`tests/helpers/level1_slice_replay.gd:142-190` contains no laser, column or wall code. Column kills are only measured by the manual `level1_column_replay_worker.gd`.

Fix:
- Drive `_spawn_laser_columns` on the slice timeline, plus the wall in deep_space.
- Count `EnemyModule.destroyed` and hull `died` events inside a lit ray.
- Add a boundary row (for example avoidance 0 on a column x) that proves a kill is detected.

### 7. The Carrier's column window
- Warn 3.0 s and active 4.0 s are the defaults of `_spawn_laser_columns` (`level_1_director.gd:218`). `LaserRay.warn_duration` defaults to 0 (`laser_ray.gd:31`). The 55 s columns are therefore lethal from 58 to 62 s, which disproves "59.0 s, after the columns fade".
- Life from y −240 is about 22 s: (1164 + 144 + 240) / 70. The longest gap between column events is 16 s.
- Option A (59 to about 81 s) overlaps both the 55 s set and the 78 s set. The merged columns sit at 150 / 300 / 550 / 700 / 950 / 1100, with a widest gap of 250 px, against the 288 px needed. No x works.
- Feasible choices:
  - Option C (59 to about 77 s) needs only the 55 s lanes, about 444–556 or 844–956. The Ph9 jammer at x 480 (alive 62–89 s) sits in the first one.
  - A spawn after 62 s needs only the 78 s lanes, about 294–406 or 694–806.
- `_column_conflicts()` has no end-time filter, so it can't be reused unchanged.

### 8. Carrier drift, avoidance, speed and EMP
- Sway is clamped only to the view x.
- `ship_config.gd:24-26` sets avoidance 1.0 and margin 60 by default, which contradicts the §2.6.4 row "y advances at 70 ± 1".
- `enemy_mover.gd:225-236` caps the requested speed, so (40, 70) under a cap of 70 becomes about 61 px/s downward.
- `test_enemy_dual_mode.gd:684-694` pins each AI enemy's hazard settings, so the Carrier needs a row there.
- The player's EMP Blast halts the Carrier for up to 5 s each time.

### 9. Level 2 compile
- `level_2_waves.gd:9,34` calls `builder.gunship()` on a typed `WaveBuilder`. `level_2.tscn:5` loads that script, so `test_project_load_integrity.gd` fails once the builder is removed.
- `test_station_reinforcements.gd:363` uses `WaveBuilder.GUNSHIP`.

### 10. The transparency sweep
`test_entity_sprite_transparency.gd:151-171` collects only `Sprite2D.texture` and `AnimatedSprite2D` frames. `EnemyModule.wreck_texture`, the door textures and the core textures are never seen.

### 11. Beam and nova against immune parts
The player's beam and nova emit damage directly and skip `deflects_hit`, so the part's own vulnerability check is the only guard. §4 promises that the plated core deflects the beam and the nova, but no task's sections carry that row.

### 12. Plan sections
- t5 needs §1.3 (the `EnemyShield` facts).
- t6 needs §2.9 (lights).
- t7 needs §1.3 (the `EnergyRing` API) and §2.8 (owner-group exemption).
- t12 needs §2.7 (Assault mounts fire only inside the view; the missile bank) and §2.16.
- §2.1's "Light … (§2.11)" should be §2.9.
- Every listed heading does exist.

### 13. Framework details
- The nova hits every enemy on the map (`plasma_nova_module.gd:34-41`), not "every module in range", and the dash does not target parts. Correct the wording.
- `EnemyModule._ready()` must call `DefenseProfile.apply_to($HurtBox)`, because `base_enemy.gd:89-90` applies the profile to the root hurtbox only.
- `max_health` 0 must skip `Health`: `health_component.gd:22` clamps current health to 0, so an indestructible part reads as dead.
- Put the wreck tint on the `Sprite` child, because `beam_behavior.gd:105` overwrites the target's tint.
- Mounts with arcs wider than 180° turn the shortest way (`turret_mount.gd:316`) and so cross the blocked sector. Specify that they turn within the arc and add a 300° row.
- t2's acceptance claims every §2.1 / §2.2 row, but the mount rows and the unique-pool-name row are t3's.

### 14. Behaviour gaps
- A burst stops when `can_fire` drops (`burst_cannon_mount.gd`), so during VENT the brain must keep `can_fire` true while `mount.is_committed()`.
- The enemy rocket mask is 128 | 512 (`enemy_rocket.gd:17`), so a rocket curving back can hit its own ship's parts. Acknowledge it or exempt the launcher's parts.
- Open Space PANIC: say whether the retreat or the 900 px leash wins.
- The "one side safe" row needs the player stub to follow the port side, because the Carrier turns its live battery toward the player at 0.35 rad/s.
- The Carrier's ring hurts enemies outside its owner group, such as the Ph9 jammer and other planet_approach traffic. Constraint 4 should consider that.

### 15. Gates and acceptance criteria
- Add to t4 "every level-1 replay green": the deep_space 3.5 s heavy joins `test_level1_ph8_attacks.gd`'s slice.
- Add `test_level1_ph9_attacks.gd` to t12.
- Add a Heavy count boundary of "one extra at the peak fails".
- Replace "a heavy at 72 s fails" (trivial) with a boundary derived from the config.
- Add a spill-over row in the Ph5 pattern: no heavy, rocket or launched child outlives the next enemies-cleared section's last trigger.
- Write the Assault hangar rows out: a port hangar destroyed before 3.0 s means only the starboard launch at 7.0 s. Add an emergency deployment row with a destroyed hangar.
- Add an engaged-launches control to t10.
- Optional: a measured, ungated heavy shots-per-second row. `test_level1_fighter_fire_density.gd:20-24` counts only fighters and Gatlings.

### 16. Sizing and ordering
- The t4 corridor exit probe likely costs more than 2.0 s; earlier probes cost 1.95 / 3.2 / 6.7 s.
- t2's 1.5 s must cover about 10 real-physics rows.
- The 238 s escalation line sits inside the run-to-run noise.
- t9 might change body, hurtbox or module geometry while t11 and t12 measure against it.
- The hub bearing 22.5° on the 2600 ring is about 120 px from `HubDefenseSite` and `SectorJammer`; only −67.5° works as a fallback.
- t9 at medium is defensible.

### 17. Earlier deferral
DECISIONS.md:3533 assigns "EMP on bonus drone, station, Ph8 turrets / fences" to Ph10 or Ph11.

---

## Reviewer A — full report


Blocking:
1. Interior Gunship parts are shielded by the vulnerable full-body hull hurtbox: bullet/rocket consumed at the outline (bullet.gd:117-140, hurtbox_component.gd:41-49, homing_missile.gd:273-300). §2.1/§2.4.1/§2.5/§2.6.2; t2,t4,t5,t9. Fix: geometry rule (exposed part hurtbox reaches outline by >= one bullet step ~16 px) + real-physics row per part in both harnesses; or another hull rule; §2.5 say cannon shield protects only cannon HP (head-on bullet still damages hull).
2. EnergyHitScan VICTIM_GROUPS (energy_hit_scan.gd:17) has no enemy_parts; is_exempt (:37-42) only host + owner group -> "EnemyBeam kills a module" row fails; adding enemy_parts makes carrier_pulse_ring damage own parts. §2.1, §2.7; t2,t7. Fix: drop EnemyBeam claim (keep LaserRay, laser_ray.gd:81-127) or add group + exempt parts of exempt host + row "ring never damages own parts".
3. Gunship rear rockets (rocket_battery_mount.gd:42-53 persist pools; pursuit_rocket.tscn:37 max_time 6.0) outlive it in ENEMIES_CLEARED cloud_descent; level_director.gd:170 waits on any child. Contradicts DECISIONS.md:1954, :1555, :2940 without saying why. Deadline lacks rocket-flight term; Assault gate covers only battery/cannon. §2.4.4, §2.5, §2.12; t5,t11. Fix: add max_time to per-entry deadline + gate missile window on budget (remaining >= missile_window + max_time) with boundary row, or no missile mount in Assault ENEMIES_CLEARED; record in DECISIONS.
4. Carrier Assault sway clamped only to view x; constraint 1 (§2.13) needs part x-span clear of lit columns from fixed spawn x; at 40 px/s for ~19 s before 78 s columns it can be anywhere. Avoidance never set (ship_config.gd:24-26 default 1.0 margin 60) bends the constant descent; max_speed 70 caps (40,70) to ~61 px/s vertical (enemy_mover.gd:225-236). Also HAZARD_PROFILES in test_enemy_dual_mode.gd:684-694. §2.6.3, §2.13, §2.6.4; t6,t12. Fix: assault_sway_leash around anchored x, check band vs columns; explicit hazard profile + HAZARD_PROFILES row; Assault speed cap >= ~81 px/s.

Minor:
5. level_2_waves.gd:9,34 calls builder.gunship() (typed WaveBuilder -> compile fail / project-load gate); test_station_reinforcements.gd:363 uses WaveBuilder.GUNSHIP. Not listed in §1.1 S7/S8, §2.4.6, t4 AC. Fix: list both; rename to heavy_gunship(), keep rail.
6. plasma_nova_module.gd:34-41 nova hits every enemy on map, not "in range"; dash does not target parts. t2 wording.
7. base_enemy.gd:89-90 applies DefenseProfile only to root hurtbox; EnemyModule._ready must apply_to($HurtBox). t2.
8. health_component.gd:22 clamps current to 0 when max 0 -> indestructible part reads dead; say max_health 0 skips Health. t2.
9. turret_mount.gd:316 shortest-way turn; arcs >180 turn through blocked sector; specify + 300 deg row. t3.
10. beam_behavior.gd:105 writes target tint; put wreck tint on Sprite child. t2.
11. burst_cannon_mount.gd header: losing can_fire stops burst; brain must keep can_fire while mount.is_committed() during VENT. t5.
12. DECISIONS.md:3533 assigns "EMP on bonus drone, station, Ph8 turrets/fences" to Ph10/Ph11; list in §6.
13. test_level1_fighter_fire_density.gd:20-24 counts only fighter/Gatling; suggest measured, reported (ungated) heavies shots/s row. t11,t12.
14. Open Space PANIC: retreat vs 900 px leash precedence unstated; "one side safe" row needs player stub following port side (carrier turns live battery at 0.35 rad/s). t6,t7.
15. enemy_rocket.gd:17 mask 128|512: own pursuit rocket can hit own ship's parts; acknowledge or exempt. t5,t7.

Verified correct: BaseEnemy wiring/defence/brain-then-mover/death/EMP/tow/repair; HurtBox order; ArmorQuery/ArmorPlate._resolve/Bullet deflect; EnemyShield; TurretMount API, variants, pools, DefenseTurret builder; EnergyRing defaults; Heavy Shell 160 px/s 20 dmg 12 s/1800 px; EnemyMover API; AnchorIdle, EngagementBudget, Steering, TargetInfo, LOS, world_anchored_x, enemy_spawned_orphan, LaserTender pattern; Ram homing_point precedent; StationTurret; beam/nova target groups; LaserRay 9999 on 512; legacy gunship facts and level-1 rows 3.5 / 50.0 / 62.0 / 62.8; hub 2600 ring free bearings; privatise; brain writes mover.max_speed precedent. Scope: all listed requirements covered; Ph18/19 deferrals reasoned; S2 ArmorPlate change justified.

---

## Reviewer B — full report


Decomposition, dependency chain and hub placement are largely sound; level 1, the deadline gate and two test rows are not, and several plan claims there are false against the code.

Blocking:
1. cloud_descent deadline almost certainly unmeetable at a 14 s budget, no pre-approved lever (§2.4.3, §2.12, §2.16; t4, t11). test_engagement_deadline.gd:236-260, MARGIN 0.5 at :28; 62.0+0.8 s heavy rel = -13.2 -> engage + attack_window + exit + 0.5 <= 23.2 s, so window + exit <= 8.7 s; Missile Corvette measured corridor exit already 8.72 s (DECISIONS.md:2138) with faster exit (280 / accel 240 / turn 1.2 vs heavy 260 / 120 / 0.9). Fix: derive engage_seconds from the deadline (~10-11 s) or pre-approve ordered levers (engage_seconds to a floor, then exit_speed), legal only while attack-in-budget stays green.
2. Rear rockets outlive the heavy; deadline ignores them (§2.5, §2.12; t5, t11). rocket_battery_mount.gd:51 persist: true (pinned by test_level1_specialist_spawns.gd:1587); level_director.gd:170 waits on zero container children. Same reason no Missile Corvette is in ENEMIES_CLEARED. Fix: close the Missiles mount in Assault from budget expiry / DISENGAGE and gate it like the batteries, or add the rocket tail to the deadline row; boundary row like test_a_corvette_in_cloud_descents_last_wave_misses_the_timeout_on_the_rocket_term_alone.
3. §2.12 ignores the level-start laser wall (§1.1 S9, §2.12; t11). level_1.tscn:46 static 12-ray LaserWallWave over x 0-672, lethal ~3-7 s into deep_space, not in laser_column_schedule(); DECISIONS.md:3421 "Static things in deep_space must clear both." Deep_space heavy spawns 3.5 s at world x 640, 112 px hull inside the span. Lever (2) .at(-160, -500) = x 320, inside the wall. Fix: name the wall in §2.12 and the column row (reuse _wall_wave_row()); lever to +160 only.
4. The column row as written cannot fail (§2.12; t11). tests/helpers/level1_slice_replay.gd lights no columns (run() :142-190 has no laser/column/wall code); column kills only measured by manual level1_column_replay_worker.gd. Fix: replay lights the section's columns via _spawn_laser_columns on the slice timeline (+ wall in deep_space), counts EnemyModule.destroyed / hull died inside a lit ray; boundary row (hazard_avoidance 0 on a column x) proves detection.
5. Carrier column window on wrong timing; default option infeasible (§2.13; t12). warn 3.0 / active 4.0 are _spawn_laser_columns defaults (level_1_director.gd:218), LaserRay.warn_duration export defaults 0.0 (laser_ray.gd:31); "read from the LaserRay exports" gives 55-59 s and the false "59.0 s, after the 55.0 s columns fade" — 55 s columns are lethal 58-62 s. Life from y -240 ~22 s ((1164+144+240)/70, arena_camera.gd rect); no column gap that long (62->78 is 16 s), so constraint 1 cannot be met as worded. Option A (59 -> ~81 s) overlaps both 55 s and 78 s sets; merged x 150/300/550/700/950/1100, widest gap 250 px vs 288 needed (±88 span + 28 beam half-width + 28 margin per side). Fix: read window from director params or hoist into schedule data; restate constraint 1 as per-column lit-window overlap; reorder options so a feasible one leads (C: 59 -> ~77 s, only 55 s set, lanes ~444-556 or 844-956, but Ph9 jammer x 480 alive 62-89 s in the first; spawn after 62 s needs only 78 s set, lanes ~294-406 or 694-806); don't reuse _column_conflicts() unchanged (no end filter).
6. Carrier x and life not actually fixed (§2.6.3, §2.13; t6, t12). Assault sway follows the player at up to 40 px/s x engine factor, clamped only to view rect; ShipConfig.hazard_avoidance defaults 1.0 (ship_config.gd:24), bends the constant 70 px/s crossing (contradicts §2.6.4 "y advances at 70 ± 1"); player EMP Blast halts it up to 5 s each. Fix: Assault sway leash (± N px around spawn x) sized into the lane margin; decide avoidance vs CROSS explicitly; bound life incl. EMP halts or accept and record; t12 row with player stub at each view edge for the whole crossing, no module enters a lit column.
7. Removing gunship() breaks Level 2 (§1.1 S8, §2.4.6; t4). level_2_waves.gd:34 live builder.gunship() with builder typed WaveBuilder.new(); level_2.tscn:5 loads it -> test_project_load_integrity.gd fails. test_station_reinforcements.gd:363 uses WaveBuilder.GUNSHIP, not in §2.4.6. Fix: t4 converts/deletes the Level 2 row and renames the reinforcements assertion to HEAVY_GUNSHIP; correct S8.
8. Transparency gate never sees wreck/door/core textures (§2.10; t9). test_entity_sprite_transparency.gd:151-171 collects only Sprite2D.texture and AnimatedSprite2D frames; EnemyModule.wreck_texture, hangar door and core plating states are exported properties. Fix: walk Texture2D-valued properties in scope, or test_ph10_sprites.gd runs the same opaque-fraction check on every module/hangar/core texture; put in t9 acceptance.
9. No row for beam/nova against a non-vulnerable part (§2.1, §2.6.4, §4; t2, t6). §4 says plated core "deflects real bullets, the beam and the nova", but no task's sections carry it; §2.6.4 bullets only; §2.1 beam/nova rows use vulnerable parts. Beam and nova emit directly and skip deflects_hit, so the damage handler's vulnerability check is the only guard. Fix: beam and nova rows vs a closed vent, the plated core and a closed hangar in §2.1 (fixture) and §2.6.4.

Minor:
1. planSections gaps: t12 needs §2.7 and §2.16; t5 needs §1.3 (EnemyShield facts); t7 needs §1.3 (EnergyRing API) and §2.8 (owner-group exemption); t6 needs §2.9. §2.1 "Light … (§2.11)" should be §2.9. Every listed heading resolves.
2. t2 acceptance overreaches ("every §2.1 / §2.2 row" includes t3's mount and build_mounts unique-pool rows).
3. t4: deep_space 3.5 s heavy joins test_level1_ph8_attacks.gd 3.0 s slice (level1_slice_replay.gd keeps every entry of a wave) -> add "all level-1 replays green". t12: add test_level1_ph9_attacks.gd (62.0 s Carrier joins the jammer slice).
4. Hub lever bearing 22.5° on the 2600 ring = (2402, 995), ~120 px from HubDefenseSite (2520, 1040) and SectorJammer (2260, 980); only -67.5° works as gunship fallback.
5. Assault hangar rows underspecified (§2.8 destroyed-hangar row in Open Space terms); spell out HangarPort destroyed before 3.0 s -> only starboard launch at 7.0 s; add emergency-deployment row with a destroyed hangar.
6. Gate allotments: t4 2.0 s includes a corridor exit probe over both start sets (past probes 1.95 tender, 3.2 Hacker, 6.7 Mine Layer); t2 1.5 s must cover ~10 real-physics rows at 0.25-0.4 s; 238 s escalation line within ±1-3 s noise.
7. Weak boundaries: no "one extra heavy at the peak fails"; "a heavy at 72.0 s fails" is trivial (72 + 14 > 86) — derive from config like the fighter rows.
8. t9 parallel with t11/t12: art changing body/hurtbox/module geometry invalidates column measurements — freeze geometry in t9 or make t11/t12 depend on t9.
9. Carrier pulse ring hurts enemies outside its owner group (Ph9 jammer x 480 alive 62-89 s, other planet_approach traffic); constraint 4 should consider it.
10. t10 tests only the negative (unengaged launches nothing); add engaged-launches control.
11. No spill-over row for heavies (Ph5 pattern: no heavy, rocket or launched child outlives the next ENEMIES_CLEARED section's last trigger).
12. t9 possibly undersized at medium (~19 sprites, 288 px scaling rule, scene wiring, new test file); defensible either way.

Verified correct: four level-1 gunship rows (level_1_director.gd:348-350, 986-987, 1016-1018); Cloud Descent gunships never fired (enemy_path_mover.gd:62 disables physics; gunship.gd starts its burst timer only in physics); legacy cloud_descent peak 3 (50 s rail culled after ~14.8 s); section order deep_space -> asteroid_belt -> station_assault -> planet_approach -> cloud_descent, cloud_descent timeout 10 s default (level_section.gd:35), last trigger 76.0 s; column x/times; specialist peaks 12/12.5, 7/7.5, 6/10; drone headroom planet_approach 7/9 vs 12/15 (up to 4 carrier drones fit); fire-density schedule pin covers deep_space only; hub free bearings, draw 19 (157.5°) and draw 20 (-112.5° on 3400) clear interactables by >perceive radius (~1604 vs 900, ~1697 vs 1100), anchors >1000 px apart (closest Sniper 1218 px); GUT 224.17 / 225.05 s with 2888 tests at Ph9 close; dependsOn matches §3; roster sweeps pick up new scenes automatically.
