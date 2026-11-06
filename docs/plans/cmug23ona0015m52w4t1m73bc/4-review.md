VERDICT: APPROVED

# Plan review: Enemy rework phase 8 (energy weapons, defense turrets, Twin-Laser Drones), round 1

Round-1 verdict: **CHANGES_REQUESTED** (superseded by round 2 below; the current verdict is on the first line of this file).

Reviewed `3-plan.md` (revision 1), `1-context.md`, `2-research.md` and `tasks.json` against the code on `agent/auto-dev` @ `ca33df4`,
CLAUDE.md, tests/README.md → Gate time, DECISIONS.md (Phases 1–7 and the planned Phase 8 section at line 2856) and the IDEAS
§6.5 / §6.10 / §11.3 text. I ran `tests/integration/test_level1_specialist_spawns.gd` to get the measured lives and peaks used below.

The design is sound and well reused: a new hand-tickable `EnemyBeam` beside `LaserRay` (which really is a 9999 one-hit kill on a `Timer`,
so S1 holds), direct-emit damage through `Hazards.hurt_box_of`, the Support Ship's sustained `EnemyShield` path for the generator,
`BulletPool` root pools that keep the grandparent rule, `boost()` for committed runs, segment hazards that leave the circle path
bit-identical, measured exits and attack-in-budget rows. R8.24's four test requirements each map to rows in both harnesses. Four problems
must be fixed before unattended implementation: the gate-time budget does not add up, the planned Planet Approach placement fails the
frozen density gate, the Deep Space turret group's power source is placed on one of level 1's own laser columns, and the advertised parallel
lanes have tasks editing the same files.

## Blocking

### B1. The gate-time budget is wrong and too small for the two measured exits (t1, t14, t19)
- **Evidence:**
  - The §2.20 allotments sum to **26.9 s**, not 26.4 s: 2.0+1.0+1.5+1.5+1.5+1.5+1.5+2.0+1.5+0.5+2.5+2.0+1.0+0.2+0.2+0.3+1.2+5.0.
  - The phase therefore ends at ≤ 218.44 − 10 + 26.9 = **235.3 s**, not 234.8 s. DECISIONS.md:2924 copies the wrong figure.
  - t14 and t19 must measure two new corridor exits, for the drone and the tender, over `corridor_starts()`. Each is a 2166-run probe.
    - The current `test_level1_specialist_spawns.gd`, with three such probes (corvette, support, Mine Layer) plus the view-grid probes,
      took **20.0 s** in my run.
    - Ph7's single Mine Layer probe cost 6.7 s (tests/README.md, Ph7 t15 row), and t15 grew GUT by +7.6 s.
    - The plan's own cost table says "a measured exit probe ≈ 1–7 s".
  - Yet t14 is allotted 1.0 s and t19 5.0 s. t19 also has to pay for at least three slice replays (≈ 0.6 s each), the density rows and the
    deadline guards.
  - A realistic t14 + t19 is about 10–14 s against the 6 s allotted, which puts the phase at or over 240 s.
  - "Share a scenario or convert to hand-ticked form" cannot shrink a probe.
  - P4 also lowers t1's floor from the research's recommended ≥ 15 s (`2-research.md` §6) to 10 s with no stated reason, although §1.1
    says the research's recommendations hold "unless §1.1 says otherwise".
- **Fix:**
  - Correct the sum and the end figure in §2.20 and DECISIONS.
  - Budget each corridor probe explicitly, using the Ph5/Ph7 figures: about 3–7 s each for t14 (memoised so that t19 reuses it through
    `SpecialistExitProbe`'s process-wide memo with identical keys), and say which file pays for it.
  - Either restore t1's floor to ≥ 15 s or show that the corrected total still ends ≤ ~235 s with that margin.

### B2. The Laser Tender at planet_approach 62.0 s breaks the frozen 2.5× specialist gate (t19, §2.18)
- **Evidence:**
  - Measured lives from the gate's own output:
    - SNIPER 16.23 s
    - BOMBER 18.38 s
    - RAM 10.19 s
    - MISSILE_CORVETTE 16.89 s
    - MINE_LAYER 22.24 s
  - planet_approach's limit is 7.5 (frozen 3 × 2.5). Today's peak is 7 at 98.0 s.
  - Specialists alive from the pinned rows (`test_level1_specialist_spawns.gd:53-90, 557-562, 804-807`):
    - At **65.7 s**: Mine Layer (47 → 69.2), bomber (58 → 76.4), two snipers (65 → 81.2) and a ram (65.7 → 75.9) = 5. The rams from
      55 s died at 65.2 / 65.5 s.
    - At **75.5 s**: bomber, the 65 s snipers ×2, the 65.7 s ram and the 75.5 s snipers ×2 = 6.
  - The tender's life is engage 10 + 0.6 + exit. Its two drones are launched within that window and then live engage 8 + cycle + exit.
  - Adding the tender and its pair gives **8 at 65.7 s** and **9 at 75.5 s**, both > 7.5.
  - The plan says "the new lives must not raise either above its limit", and DECISIONS:2916 already records the 62.0 s placement, but nobody
    computed it.
- **Fix:**
  - Compute the alive curve before choosing the wave.
  - The only low-density window in planet_approach is its start (0–2 alive until 28 s; existing waves at 2.0 / 5.0 s). Choose the wave from
    that curve, using the tender's and drones' worst-case lives (state the launch-time bound the drones' interval starts from).
  - Record the placement in DECISIONS, and keep the lever only as a fallback.

### B3. Deep Space's turret group puts its power source on a level-1 laser column, so every run shuts the group down (t19, t17, §2.16, §2.18)
- **Evidence:**
  - `level_1_director.gd:64-68`: deep_space lights `LaserRay` columns at x = 128 / **640** / 1152 at 6.0 s (warn 3.0 s, active 4.0 s;
    `_spawn_laser_columns`, `:172-186`).
  - Each column is a 56 px strip from y −380 down 1536 px, with hit mask 128 | 256 | 512 and 9999 damage.
  - `ArenaCamera` is pinned at (640, 360) (`level_1_director.gd:168`). `WaveManager` spawns at `cam.global_position + cam.offset +
    offset × WORLD_SCALE` (`wave_manager.gd:194`). So `turret_group(...).at(0, -220)` puts the group at x = **640**, and the power source
    slot (0, −60) is at x = 640 too.
  - The group spawns at 3.0 s (3.5 s in game, by the wave-order quirk, DECISIONS:1276) at y ≈ −140. At 9–13 s, when the column is lethal,
    it has drifted to y ≈ 190–430, inside the strip. The column kills the power source and powers the whole group off about 5 s after it
    enters the view, every run.
  - No gate sees this: the slice replays drive `WaveManager` only, and §2.16 notes that "no test replays" the columns.
  - t17 measures column kills but does not depend on t19, so it will measure a level without the group.
- **Fix:**
  - Place the group so that no static member comes within (28 + member body radius) px in x of any deep_space column lit during its drift
    life.
  - Add a t19 row that checks every static Ph8 member's x against `_section_schedules` over its computed drift life, so the row fails on
    today's (0, −220).
  - Order t17 and t19, both in `tasks.json` and in the text: either t17 measures after the Ph8 placements, or it says it is pre-placement and
    t19 re-checks.

### B4. Tasks advertised as parallel lanes edit the same files (task dependencies)
CLAUDE.md allows no worktrees. §3 explicitly advertises the parallel lanes. Phase 7's review (M5) required these to be chained. Pairs with no
dependency path between them that edit the same files:
- **t6 ∥ t12 (and t11 ∥ t8 / t9 / t10 / t12 / t13):**
  - Shared files: the hand `ROSTER`s of `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd` and
    `test_enemy_contact_damage.gd`, `test_wreck.gd` `_SHIP_SCENES` (`:33`), `test_base_enemy.gd` (`_MIN_ROSTER_SIZE` `:61`, the tow table
    `:492`), `test_enemy_dual_mode.gd` and `assault/scenes/systems/wave_builder.gd`.
  - t12 depends only on t5, so it can run alongside t6. t11 depends only on t7, so it can run alongside t8, t9 and t10.
- **t7 ∥ t8:** both extend `mounts/turret_mount.gd` (the shared cycle), `turret_mount_scenes.gd` (`scene_for` map), `test_defense_turret.gd`
  and the brain's StateLight / `can_fire` logic. t11 also edits `test_defense_turret.gd`.
- **t3 ∥ t5:** both extend `enemy_beam_scenes.gd` (t3 "gains the ring scene", t5 adds `twin_beam.tscn`) and `BEAMS.md`.
- **t14 ∥ t16:** both edit `laser_tender.gd` / `.tscn` (idle vs cradle wiring), `twin_laser_drone.tscn`, `test_laser_tender.gd` and
  `test_twin_laser_drones.gd`.
- **t17 ∥ t19:** both edit `assault/scenes/levels/edelia/1/level_1_director.gd`. See also B3.
- **Fix:** chain them in `dependsOn`. For example:
  - t6 → t7 → t8 → t9 → t10 → t11 → t12 → t13 → t14 → t16 (or any single order through every roster-editing task);
  - t3 → t5;
  - t17 → t19.
  The cost is wall-clock only. Delete or correct the "Parallel lanes" sentence in §3.

## Minor

### N1. The player sees half the beam cadence, and the i-frame row cannot happen (t2, §2.2)
- **Evidence:**
  - `player_base.gd:32` sets 0.5 s i-frames on a `Timer` (`_start_invincibility()`, `:144-146`).
  - Godot runs physics before idle. A beam whose `rehit_interval` is exactly 0.5 s re-hits on the physics tick of the frame in which the timer
    times out, which is before the timeout. The player is then still invincible, so in play the player is hit every **1.0 s** while enemies
    are hit every 0.5 s. That contradicts "both sides see the same cadence".
  - The §2.2 row "two hits 0.3 s apart deal one" cannot come from one beam (0.5 s re-hit). In a hand-ticked test the player's `Timer` never
    advances anyway.
- **Fix:**
  - Either set `rehit_interval` slightly above the i-frames (for example 0.55 s), or state the player's 1.0 s cadence.
  - Rewrite the player row as: real frames at 8×, and count hits over 2 s against the expected number.

### N2. The telegraph line is thinner than the research's own rule (t2, §2.1 "Drawing")
- **Evidence:** the plan draws a **2 px** telegraph line at alpha 0.55. `2-research.md` §1 says "every beam kind has a harmless warning line
  ≥ 3 px". I checked the cited source (sparen.github.io ph3u1l9): "anything under 18 has a high chance of having an invisible or near-invisible
  delay laser".
- **Fix:** set a minimum telegraph width of ≥ 3 px (or tie it to `hit_half_width`) as a scene export, with a row that reads it.

### N3. The heavy emplacement's `turn_rate` override has nowhere to live (t6, t11, §2.7, §2.9)
- **Evidence:** §2.7 instantiates mounts at runtime from `TurretMountScenes.scene_for(slot.variant)`, and `TurretMountSlot` exports only
  `variant` and `rest_bearing_deg`. §2.9's "an export override on the slot's mount instance" has no authored instance to override.
- **Fix:** t6 adds `@export var turn_rate_override := -1.0` (or a generic override dictionary) to `TurretMountSlot`, and t11 uses it.

### N4. The hub site's clearance sweep is under-specified (t18, §2.17)
- **Evidence:**
  - `_element_radius()` is reached only through `_space_elements()`, which walks the children of `TacticalSpace`
    (`test_sector_hub_patrol.gd:856-861`). The site lives under `EnemyContainer`, so a `TurretGroup` case there is dead code unless a new sweep
    walks `EnemyContainer`.
  - The site's element radius is about 1360 px (lance range 1100 + 260 offset). The Bomber's anchor (1202, 1202)
    (`sector_hub.gd:49-51`) is about 1330 px from the site centre (≈ 2520, 1040), so whether existing patrols must clear the site decides the
    outcome.
  - The plan only requires the *new* patrols to clear it. If the existing patrols must too, the "3000 px ring" lever cannot clear every
    1300–1900 px anchor: a point on that ring 22.5° from a 1700 px anchor is only about 1570 px from it.
- **Fix:** name the sweep (over `EnemyContainer` `TurretGroup` / `LaserFence` children), state which patrols it covers, and state the
  boundary case it adds.

### N5. No task owns `WaveBuilder.turret_group()` / `TURRET_GROUP_ASSAULT_PAIR` (t9, t19)
- **Evidence:** they appear only in §2.18 (plan line 712). §2.10 and t9 build the preset but never add the helper.
- **Fix:** give the helper to t9, next to the preset, with a row.

### N6. Some `planSections` are missing (t3, t4)
- **t4:** its acceptance bound "closest approach ≥ `hit_half_width` + 14 px" needs the twin beam's `hit_half_width` (10). That value is only in
  §2.1's export table, which t4 does not list. Add "2.1", or write the number into §2.6.
- **t3:** its description edits `EnemyBeamScenes` (defined in §2.1), but t3 does not list 2.1. Add it.
- Tasks t2–t19 are told their allotments are "in plan §2.20", which they do not receive. The descriptions repeat each number, so this is
  acceptable, but say so in "For every task".

### N7. Complexity and size (t9, t18, t19)
- **t19:** places three new kinds, consumes two measured exits, has at least three slice replays, density, spill-over and deadline guards for
  four kinds, and the largest allotment. That is more than Ph7's *medium* t15, which needed levers to fit. Mark it **large**.
- **t18:** a seven-member preset with a fence, two patrols, a new sweep and frame-time notes. Consider **large**.
- **t9:** three entities (coordinator, power source, and a shield generator with a brain and tethers), each with roster gates and dual-mode
  cases. Consider splitting the shield generator into its own task after t9.
- No task carries a `model` field. That is consistent with Phases 6–7, so it is not a finding.

### N8. The laser fence frees itself before its posts' explosions finish (t10, §2.11)
- **Evidence:** `BaseEnemy._on_health_changed` calls `_explosion_effect.explode()` (`base_enemy.gd:247`). `ExplosionEffect` spawns its
  particles into `actor.get_parent()` (`explosion_effect.gd:49-51`), which for a post is the `LaserFence`. The fence "frees itself when both
  posts are gone", which cuts off the second explosion. In Assault the fence's drift also carries the particles.
- **Fix:** explode into the fence's parent, or have the fence free itself after a short delay. Add a row.

### N9. Two semantics the plan leaves unstated (t9, t6)
- **(a) Generator vs fence:** the shield generator calls `attach(member.hurt_box)` on every member. A `LaserFence` member has no hurtbox, so
  it is silently skipped and its posts are never shielded. State whether posts should be shielded.
- **(b) Escape penalty:** turret members default to `counts_as_escape = true` (`base_enemy.gd:30`, `score_tracker.gd:220-227`). Every turret
  that drifts out of Assault, including dark (unpowered) ones, cuts the player's combo. Decide this, for example `counts_as_escape = false`
  in the structure configs (the `bonus_drone_config.tres:11` precedent), and record it.

### N10. R8.5 "rotate the beam around an anchor point" is reinterpreted (§7)
- **Evidence:** IDEAS §11.3 lists this under the *Twin-Beam / Endpoint Laser*. §7 maps it to an emitter beam on a rotating mount. The rig
  already orbits in hub idle (§2.14), with the beam off.
- **Fix:** either list the endpoint-rotation mode in §6 with a reason, or add a small rig mode, a lit orbit, to t12 or t14.

## Checked and confirmed (no finding)
- **`BaseEnemy` (`base_enemy.gd:71-76, 115-120, 148`):**
  - privatises the config in `_init` and `_enter_tree`;
  - ticks the brain and steps a mover only if one exists;
  - `is_ai_driven()` is false without a mover.
- **`BulletPool`:** the container is the grandparent (`bullet_pool.gd:63`).
- **`HazardInfo` and `Hazards`:**
  - `HazardInfo` is circles only (`hazard_info.gd:83-90`);
  - `Hazards.around` goes through `contains` (`hazards.gd:30-34`), and so do all its consumers (Ram, Fighter, Sniper, Mine Layer, mines), so
    segment-aware `contains` is enough;
  - `accel_at` and `penalty_at` are zero for a segment info with no pull.
- **Steering and `EnemyMover`:**
  - The `context_avoid` structure matches §2.6 (`steering.gd:236-299`, 16 slots).
  - `EnemyMover.boost` ignores avoidance but keeps the penalty, drift and constraint (`enemy_mover.gd:114, 215-272`).
  - `release_constraint()` and `constraint_released()` exist.
  - `_avoid`'s own-claim drop is at `:286-289`.
- **`LineOfSight`:** `_blocks`, `BLOCK_MASK = ENVIRONMENT | HAZARD_CONTACT`; past the recast cap the line counts as clear
  (`line_of_sight.gd:16-50`).
- **`EnemyShield` and the Support Ship:** `attach()` returns a bool; `sustain_mode` and `heartbeat` 0.3 exist; `_make_shield()` follows the
  same path (`support_ship_brain.gd:636-655`).
- **`BeamBehavior` and `is_laser_blocking`:** the player's beam honours `is_laser_blocking()` and targets centres within 12 px
  (`beam_behavior.gd:56-100`).
- **Ram armour:** the Ram refuses direct emits while armoured (`ram_corvette.gd:128-133`).
- **Spawning and scoring:**
  - `WaveManager` sets props before `add_child` (`wave_manager.gd:199-209`);
  - `ScoreTracker` tracks orphans (`score_tracker.gd:78-94`);
  - non-`BaseEnemy` spawns with `counts_*` false are handled (`:137-172`).
- **Helper signatures:** `EnemyRounds.pool_size_for(max_burst, round_lifetime, min_burst_period)`; `EnemyRocket.launch(dir, aim_point,
  launcher)` and the launcher contract; `EnemyMineScenes.export_of`; `TargetInfo.intercept`; `StateLight` `OFF / ARMED / CHARGING / COMMIT`
  and `blink_once()`; `BurstClock`; `AnchorIdle`; `EngagementBudget`.
- **Assault geometry:** `ArenaCamera.projectile_world_rect()` is the view grown by 64 px (`arena_camera.gd:52, 88`).
- **Level 1:**
  - The column schedule in §2.16 is exact (`level_1_director.gd:62-87`).
  - The deep_space 3.0 / 20.0 s and planet_approach 62.0 s waves exist.
  - The deep_space peak with the turret group (11 at 16 s) and the twin pair (≤ 10) stays ≤ 12.5. Only planet_approach fails (B2).
- **Hub:** draws 1–15 order (`sector_hub.gd:72-89`); the `_patrol_groups()` / `_element_radius()` lines cited are right.
- **Test harness and tooling:**
  - `fixture_enemy.tscn`'s `HurtBox` has no shape;
  - `_scale_clock()` / `_restore_clock()` are in `test_level1_drone_exit.gd`;
  - `SpecialistExitProbe.corridor_starts()` exists;
  - the single-writer regexes allow a mount's own `rotation` (`test_enemy_mover_single_writer.gd:35-55`);
  - every cited test file and script exists.
- **Arithmetic:**
  - the fairness inequalities hold with the §2.21 values (sweep tip 349 ≤ 360; twin 0.83 ≤ 1.88);
  - the hub radius inequalities hold (982 ≤ 1500, 1378 ≤ 1600);
  - the advance lasts 1.92 s.
- **Scope:** matches the epic. Ph9 / Ph10 / Ph11 / Ph13–Ph20 items are deferred with reasons; nothing builds ahead. The research has
  tradeoffs per option, and F1's citation checks out.

# Plan review: Enemy rework phase 8 (energy weapons, defense turrets, Twin-Laser Drones), round 2
VERDICT: APPROVED

Reviewed `3-plan.md` revision 2, `tasks.json` (21 tasks) and the planned Phase 8 section of `DECISIONS.md` (line 2856) against the code on
`agent/auto-dev` @ `70179a9`. Nothing was run except small read-only scripts (no Godot, no GUT). All 14 round-1 findings are resolved in
the plan **and** in `tasks.json`, and the arithmetic behind them is right when recomputed from the code. The fresh review found six minor
issues. An implementing agent can fix each one inside the task that owns it, and none needs the owner. None makes the gate go red, gives
wrong behaviour, collides two tasks or leaves a task unbuildable. They are listed below, with fixes, so the implementing agents see them.

## Round-1 findings: status (14 of 14 resolved)

| # | Status | Evidence |
|---|---|---|
| B1 gate time | **Resolved** | See the B1 detail below the table. |
| B2 planet_approach density | **Resolved** | See the B2 detail below the table. |
| B3 power source on a column | **Resolved** | See the B3 detail below the table. |
| B4 parallel lanes | **Resolved** | See the B4 detail below the table. |
| N1 re-hit = i-frames | **Resolved** | `rehit_interval` is 0.55 on every held beam, and a static row checks it against `invincibility_sec` read from both player scenes, with a 0.5 s boundary. The impossible "0.3 s apart" row is gone. Godot's idle `Timer` subtracts the whole frame's delta in the frame the timer is started, so i-frames expire early, never late. The 0.05 s slack therefore holds at 1× and at 8×, and the real-frame row is not flaky. See M2 for a robustness nit. |
| N2 telegraph width | **Resolved** | `telegraph_width` is an export (4 px), with a row that checks it is ≥ 3 and equals the drawn `Line2D.width`, and a 2 px boundary (§2.1). It is in t2's description and acceptance criteria, and t5 adds `twin_beam.tscn` to the row. |
| N3 turn-rate override | **Resolved** | `TurretMountSlot.turn_rate_override := -1.0` is built in t6 (§2.7, with a row and in the t6 acceptance criteria). t11 sets 1.2 on both slots. |
| N4 hub sweep | **Resolved** | See the N4 detail below the table. |
| N5 helper owner | **Resolved** | t9 owns `TURRET_GROUP_ASSAULT_PAIR` and `turret_group()`, with a real-`WaveManager` row (§2.10.1, §2.10.4, t9 acceptance criteria). |
| N6 planSections | **Resolved** | t3 and t4 list 2.1. §2.6 states the twin beam's 10 / 14 px and the 24 px bound itself. "For every task" carries the allotment line. A mechanical check finds every `planSections` entry as a heading in `3-plan.md`. #### sub-sections under a parent number have precedent in `cmufs7ek60001nm2x6d0bt2et`. |
| N7 sizes | **Resolved** | t18 and t19 are `large`. The shield generator is split into t9s (`medium`), chained t9 → t9s → t10. |
| N8 fence explosion | **Resolved** | See the N8 detail below the table. |
| N9 semantics | **Resolved** | (a) Posts are never shielded, decided in §2.10.5, with a row in t10. (b) The five static kinds set `counts_as_escape = false` in their `.tres` (owner choice 8). `ScoreTracker` reads the flag per enemy (`score_tracker.gd:142`), and `BaseEnemy._ready` copies it from the config (`base_enemy.gd:103`). There is a combo row in t6. |
| N10 anchor rotation | **Resolved** | It is listed in §6 as deferred to Ph11, with a reason, and §7 says so explicitly. |

### B1 (gate time)
- The §2.20 table sums to **33.1 s**. Recomputed: 2.0+1.0+1.5+1.5+1.5+1.5+1.5+1.2+1.0+1.5+0.5+2.5+2.0+8.5+0.2+0.2+0.3+1.2+3.5 = 33.1.
- The end figure follows: 218.44 − 15 + 33.1 = 236.54 s.
- Both corridor probes are budgeted in t14 (3.5 + 4.0 s), against Ph7's 6.7 s Mine Layer probe.
- The memo key includes `prepare` (`specialist_exit_probe.gd:118-123`). Routing both callers through one helper whose hook is a static function makes t19's calls memo hits.
- t1's floor is back to ≥ 15 s, with an ESCALATE exit.
- There is a 238 s stop rule.
- DECISIONS:2944 carries the corrected figures.

### B2 (planet_approach density)
I recomputed the gate's own `_ai_intervals` (effective trigger + delay + life) with the measured lives, from `EXPECTED` / `EXPECTED_PH5` / `EXPECTED_PH7` (`test_level1_specialist_spawns.gd:50-101, 557-563, 804-807`).
- **planet_approach before Ph8:**
  - 0 alive until the 13.6 s ram.
  - 5 at 28.4 s.
  - 6 at 32.0–32.23 s (the 16.0 s sniper dies at 32.23 s).
- **The tender at 2.0 s (the first wave in the list, so its effective trigger is 2.0 s):**
  - 5 alive at 16–22.7 s.
  - 7 at 28.4 s, which is ≤ 7.5, only while the drones are still alive.
  - The drones must be gone before 32.0 s: 12.633 + 10.753 + exit < 32.0, so exit ≲ 8.6 s.
  - This is exactly what §2.18 states and t19's acceptance criteria assert.
- **deep_space:**
  - 8 at 16.0 s and 8 at 26.5 s before Ph8.
  - 11 at both with the group (3.5 s → 31.57 s, since 1684 / 60 = 28.07 s).
  - 7 + 3 + 2 = **12** at 29.0 s with the pair, which is ≤ 12.5.
  - The pair at 20.0 s would indeed have given 13 at 26.5 s.
- **Spill-over:**
  - The pair ends ≈ 45–50 s, against the 60 s deadline of station_assault, which comes after asteroid_belt.
  - planet_approach → cloud_descent has wide slack.
- The placement is recorded at DECISIONS:2924-2929.

### B3 (power source on a column)
- `projectile_world_rect()` is centred on the pinned (640, 360), and `enemy_view_rect()` on `global_position + offset` (`arena_camera.gd:89-104`). Their centre difference is therefore exactly `offset.x`.
- `WaveManager` spawns at `cam.global_position + cam.offset + offset × 2` (`wave_manager.gd:194`) and sets the position before `add_child`. The anchoring in the group's `_ready` therefore cancels the pan exactly, camera-shake noise included, since both read the same `offset` in the same frame (`camera_shake.gd` max 8 px).
- The columns are 56 px rects centred on the ray's x (`laser_ray.tscn:231`). The member clearances are:

  | Member x | Nearest column | Clearance | Needed (28 + body radius) |
  |---|---|---|---|
  | 462 | 384 | 78 | 56 |
  | 512 | 384 / 640 | 128 | 62 |
  | 562 | 640 | 78 | 56 |

- The worst-case life is (1164 + 520) / 60 = 28.07 s. The view's highest spawn is y −460, and the slot −60 puts the member at y −520.
- Over that life every deep_space column is lit, and asteroid_belt lights none (`level_1_director.gd:62-87`).
- The row `test_ph8_static_members_clear_every_lit_column` has the revision-1 boundary.
- t17 → t19 is chained in `tasks.json`.
- The schedule refactor is feasible: every column entry is a `_spawn_laser_columns.bind([...])` callable, so `Callable.get_bound_arguments()` reads it.

### B4 (parallel lanes)
- I wrote a node script over `tasks.json` with a per-task file map taken from the plan and the descriptions:
  - the roster gates;
  - `test_base_enemy.gd`, `test_wreck.gd`, `test_enemy_dual_mode.gd`;
  - `wave_builder.gd`;
  - the mount files, `enemy_beam_scenes.gd`, `test_enemy_beams.gd`, `test_context_avoidance.gd`;
  - the drone and tender files, `test_ph8_sprites.gd`;
  - `level_1_director.gd`, `assault_pair.tscn`, `power_source.gd`.
- It finds **0** same-file pairs without a `dependsOn` path. No dependency is dangling.
- The "parallel lanes" sentence is gone. §3 lists the unchained pairs and why each is disjoint, and I confirmed them.

### N4 (hub sweep)
- The two named sweeps walk `EnemyContainer`. Their numbers check out against `sector_hub.tscn`:
  - Fire reach 1360 + the existing 300 px interactable margin = 1660 px. The nearest interactable is the Edelia survey log at 1904 px, and the Edelia planet is at 2048 px.
  - The Bomber anchor is 1328 px from the site origin, against a footprint of ≈ 416 px (+ 100).
- Each sweep has a rejecting boundary.
- The 3000 px lever is reworded.

### N8 (fence explosion)
- `ExplosionEffect.explode()` resolves `actor.get_parent()` (`explosion_effect.gd:49-51`), i.e. the fence, as the review said.
- The fence now lingers 1.0 s, counted on its own physics step, which is longer than the 0.5 s particle `lifetime` (`explosion_effect.gd:14`).
- There is a row for it (0.6 s still alive, gone by 1.1 s), in t10's acceptance criteria.

## Other things checked (no finding)
- **Scope.** §6.5, §6.10, §11.3, §18.6 and §40 of the IDEAS file are each mapped in §7. Everything else is deferred with a reason in §6: mounting on ships, the jammer link, and endpoint rotation.
- **No reinvention.** The plan reuses:
  - `BurstClock`, `EnemyRounds.pool_size_for`, `EnemyRocketScenes`, `TargetInfo`, `StateLight`, `AnchorIdle`, `EngagementBudget`;
  - the Support Ship's sustained `EnemyShield` path;
  - `LineOfSight`'s blocker rule, made public;
  - `Hazards` / `HazardInfo` (extended, with the circle path untouched);
  - `SpecialistExitProbe` and `level1_slice_replay.gd`;
  - `EventBus.enemy_spawned_orphan` (`event_bus.gd:69`, arity 1);
  - the Bonus Drone's `no_hitbox` roster idiom (`test_contact_hitbox_geometry.gd:41-66`, `test_enemy_contact_damage.gd:29-30`).
- **Groups.** `allies` (`ally_fighter.gd:30`) and `asteroids` (`asteroid_base.gd:34`) exist as the hit scan expects.
- **Brainless scenes.** `BaseEnemy._physics_process` is inert without a brain (`base_enemy.gd:115-120`). A brainless power source or post therefore relies on its own `AssaultDrift` (or the fence's) for motion, which is how the plan has it.
- **Projectile lifetime.** The burst round fits the lifetime sweep: `pulse_round.tscn` is 1400 px / 300 px/s = 4.67 s ≤ 8 s.
- **Level-1 gates.** `test_level1_fighter_fire_density.gd:144-145` filters to fighters and Gatlings, so a turret group or pair entry inside an existing wave does not perturb its measured shots/s.
- **Hub anchors.** The candidate anchors (112.5° and −157.5° on 2600) are ≥ 1000 px from every existing anchor (nearest 1218 px) and clear the planets and lore logs by more than idle + perceive.

## New findings (all minor; for the implementing agent, none needs the owner)

### M1. The drone / tender exit probe's speeds and the drone's DISENGAGE heading do not match the probe's start set (t12, t14; §2.12, §2.14), minor
- **Evidence:**
  - §2.14 calls `worst_disengage(..., [exit_speed], corridor_starts(...))`. That is one speed, so 1083 runs. Yet it budgets "≈ 2166 runs".
  - The Ph5 / Ph7 corridor probes pass `[max carry-in speed, 10.0]` (`test_level1_specialist_spawns.gd:575-586`) because a near-rest start can be the slowest.
  - Separately, §2.12 says an Assault drone exits "along −n". But `corridor_starts()` heads each start away from its **nearest** edge "exactly as the brains' `_enter_disengage()` do" (`specialist_exit_probe.gd:55-60`).
  - The probe enters DISENGAGE on a lone drone with no rig (`specialist_exit_probe.gd:170-178`), so there is no `n`. The run either never moves (capped at 20 s, so the `< 10 s` row goes red) or measures a heading rule the real drone does not use.
  - The planet_approach density bound depends on this figure being ≤ ≈ 8.6 s.
- **Fix:**
  - In t12, give the drone's DISENGAGE the shared nearest-edge exit (the same tie-break as every other brain), or define its heading when there is no rig frame.
  - In t14, pass `[max carry-in speed, 10.0]`, as Ph5 / Ph7 do. That restores the 2166-run cost the allotment assumed.
  - Record the choice in DECISIONS.

### M2. The real-frame player-cadence row can be blurred by the player's shield charge (t2; §2.2), minor
- **Evidence:**
  - `PlayerBase._apply_damage` lets a `ShieldComponent` charge absorb a hit without a health change (`player_base.gd:128-141`). Charges come from `ShipProgressionState`.
  - A real `player_fighter.tscn` with one charge loses health in 3 steps, not 4. That still passes the ±1 tolerance, so the row is weaker than it reads.
- **Fix:** count damage *events* (health decreases plus charges consumed), or zero the charges first.

### M3. The "hub frame-time note" is listed among t18's rows (t18; §2.17), minor
- **Evidence:** the Ph7 precedent (DECISIONS:2771) is a one-off headless measurement recorded in DECISIONS, not a GUT row. 2 × 600 real frames of the full hub inside GUT would cost far more than t18's 1.2 s.
- **Fix:** measure it once outside GUT and record it in DECISIONS, as Ph7 did.

### M4. t6 can run before t2 but §2.7 describes beam / ring branches (t6; §2.7), minor
- **Evidence:** t6 depends only on t1. §2.7's `power_down()` (cancel a TELEGRAPH beam / ring, FADE an ACTIVE one) and the brain's COMMIT light reference `EnemyBeam` / `EnergyRing`, which t2 / t3 create.
- **Fix:** t6 builds the burst-cannon branch only and leaves the beam / ring branches to t7 / t8, which already list those rows. Alternatively, add t2 to t6's `dependsOn` (no wall-clock cost, because t7 waits for t5 anyway).

### M5. The coverage rule counts mounts, so the hub site's heavy emplacement satisfies it alone (t9, t18; §2.10.1), minor
- **Evidence:**
  - "At least `coverage_min` 2 turret **mounts** in range": the heavy emplacement at (0, 0) has two 700 px mounts, so every point at 450 px is covered by it alone.
  - The rule cannot reject a hub site that has one shooter. Its boundary only exercises `assault_pair`.
- **Fix:** count distinct members, i.e. mounts on ≥ 2 different hosts, and keep the turret-removed boundary.

### M6. t10 is sized medium but carries a new `BaseEnemy` plus a structure (t10), minor
- **Evidence:** t10 covers:
  - a new `BaseEnemy` (the post, with every roster gate);
  - a structure with two modes, collapse, linger and world anchoring;
  - registration, avoidance-integration rows, a real-physics cover row;
  - the generator-preset row.
  
  That is closer to `large`.
- **Fix:** relabel it as large, or accept that it may run long. No re-split is needed.

## Residual risk the owner should know (not a finding)
t1 must free ≥ 15 s, and Ph7's t1 already took the easy levers (13.8 s). The remaining big file is `test_fighter_squad.gd`'s code-under-test sweep, so t1 may need the bit-identical production speed-up, or end ESCALATE. Every other task depends on t1, so an ESCALATE there stalls the epic at its first task. That outcome is cheap and correct, but it is the most likely place this phase stops.
