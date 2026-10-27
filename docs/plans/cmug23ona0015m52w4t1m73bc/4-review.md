VERDICT: CHANGES_REQUESTED

# Plan review: Enemy rework phase 8 (energy weapons, defense turrets, Twin-Laser Drones), round 1

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
