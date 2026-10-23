VERDICT: APPROVED

# Plan review: Enemy rework phase 7 (mines, minefields, Mine Layer), round 1

I reviewed `3-plan.md` and `tasks.json` against the code on `agent/auto-dev` @ `057f8d9` (the working tree is clean). I also
read `CLAUDE.md`, the Phase 4/5/6 as-built sections and the new Phase 7 section of the idea's `DECISIONS.md`, the Phase 6 plan's
§2.16, the IDEAS sections in scope, and `tests/README.md` → Gate time. I ran the full GUT suite once
(**216.4 s, 2139 tests, all passing**, the same as the plan's 216.3 s) and ran two small headless simulations of
`Steering.context_avoid()`, using scripts in `/tmp` only.

The architecture fits the codebase:
- `EnemyMine` is a subclass on the existing `EnemyOrdnance` contract.
- Pooled mines register as hazards at launch.
- Minefields reuse `ContactBlast` / `Hazards.pulse_damage`.
- One stand-in `EmpPulse` entry point covers the EMP.
- The Mine Layer copies the Bomber's pool, drop and idle shape.

It does not reinvent existing components, and the scope coverage (§7) is complete.

Approval is blocked by five concrete problems. Each is a plan edit, not a redesign:
- **B1:** three test rows promise that enemies stay outside a mine's trigger radius. The avoidance stage, with the weights this
  plan picks, cannot do that (simulated).
- **B2:** the zig-zag trail's three test rows contradict each other geometrically.
- **B3:** the plan's own numbers fail its own warning-time inequality.
- **B4:** the Boost Drive refusal is put where it burns a boost tank, breaking a documented contract.
- **B5:** the hub anchor violates the Phase 6 tactical-space clearance rule, without saying so.

---

## Blocking findings

### B1. "Enemies steer round mines" rows cannot pass with `avoid_weight` 0.5 / 0.9 at `hazard_avoidance` 0.6 (t2, t8, t10)

- **Checked:** `global/enemy_ai/steering.gd:242-275` (`context_avoid`).
  - A slot's danger is `avoid_weight · skirt · (1 − off/half_width)`, minus the threshold `1 − avoidance`.
  - Inside the radius the cone is only `half_width · (1 − (1−avoidance)/avoid_weight)` wide. For weight 0.5 at avoidance 0.6
    that is 22.5°, so the ship spirals in, holding the mine about 22° off its nose.
- **Existing pin:** `tests/unit/test_context_avoidance.gd:149-163` already pins that a *soft* profile only stays "more than half a
  radius off the centre". It does not keep a ship outside the radius.
- **Simulation:** I ran `Steering.context_avoid` against one r 80 mine, flying at 200 px/s with avoidance 0.6, integrated the way
  `_fly()` in that test does. The table gives the closest approach to the mine's centre; the trigger radius is 80.

| avoid_weight | margin | head-on | lateral 30 px | lateral 60 px |
|---|---|---|---|---|
| 0.5 (plan, PLAYER) | 24 / 60 | 14 px | 31 px | 60 px |
| 0.9 (plan, ALL) | 24 / 60 | 55 / 60 px | 61 / 65 px | 73 / 77 px |
| 1.0 | 24 | 61 px | 68 px | 77 px |
| 1.0 at avoidance 1.0 (control) | 24 | 115 px | 117 px | 122 px |

- **Ring field:** a 9-mine RING (r 200, weight 0.9) crossed at avoidance 0.6 gives a min edge of −36 / −28 px.
  - The ring's trigger zones also overlap: the chord is 137 px, against 2 × 80.
  - So "routes round it with no detonation" means going round the whole field. The soft stage does not do that.
- **Affected rows:**
  - t2: §2.1 "closest approach > `trigger_radius`" (plan line 166).
  - t8: §2.8 "a fixture with `hazard_avoidance` 0.6 routes round it with no detonation".
  - t10: §2.10 "a second pass … closest approach to every live mine > `trigger_radius`" (line 541).
  - All three fail as written. The owner-facing promise that a placed field is a lure enemies avoid also needs its real
    numbers.
- **Fix:** pick the hazard footprint from a measured table before committing rows. Two options:
  - give `HazardInfo.radius` more than `trigger_radius` (e.g. trigger + the largest enemy hurtbox + margin), with a weight of
    1.0 for ALL mines; or
  - restate the rows relative to the `registers_hazard = false` control (for example, closest approach ≥ control + X px, and no
    head-on crossing within Y px).
- **Also:** state what an avoidance-0.6 enemy actually does at a placed field (skirts it, or sometimes sets it off: a "lure").
  Keep "no AI change" only if those numbers hold.

### B2. The ZIGZAG trail rows contradict each other (t10)

- **Checked:** §2.10, plan lines 475-477 and 519-528.
- The vertices are `zigzag_wavelength/2` = 120 px apart along u and alternate ±70 along f.
- **Contradiction 1:** two consecutive rest points on opposite sides of the axis are at least 140 px apart, because they are
  140 px apart along f alone. "Alternate sides by 70 ± 4" (line 519) and "spacing 120 ± 4" (line 521) cannot both hold.
- **Contradiction 2:** rest points every 120 px of *path length* along 184 px segments do not land on the vertices. Their offsets
  come out at about +70, −21, −27, … rather than alternating ±70.
- **Contradiction 3:** each segment runs at atan(140/120) = 49.4° to u. Pure pursuit with a 60 px look-ahead tracks it, so
  "during LAY, the layer's velocity is within 35° of u" (line 528) fails for every ZIGZAG pass.
- **Fix:** define the zig-zag so the three rows agree. For example, put rest points on the vertices, with half-wavelength
  h = 100 and amplitude A = 35 (±35, so 70 peak-to-peak). That gives a chord of √(100² + 70²) ≈ 122 px and a segment angle
  of atan(70/100) = 35°. Then state the spacing and the alternation in those terms. Re-check `mines_per_pass` × spacing
  against `pass_length` / `assault_pass_length`.

### B3. The plan's own numbers fail its warning inequality (t2, t3, t9/t10)

- **Rule:** `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed` (*For every task*, §2.2). It is asserted "for
  every variant scene and for `MineLayerConfig`'s overrides".
- **HOMING:**
  - §2.2 copies the Bomber's mine for all variants: trigger 80, warning 0.25, blast 48.
  - `drop_mine` applies those same config numbers (§2.9: `trigger_radius` 80, `mine_warning` 0.25, `mine_blast_radius` 48).
  - That gives 128 / 0.25 = **512**, but HOMING needs 440 + `home_speed` 75 = **515**.
  - So the row fails for both `homing_mine.tscn` and the config.
- **PROXIMITY scene:**
  - `assault/scenes/projectiles/enemy_ordnance/mine.tscn:22` authors `warning_time = 0.5`, which gives 128 / 0.5 = 256 < 440.
    Ph4 kept the scene at 0.5 and set 0.25 in `bomber_config.tres` (`bomber_config.gd:102-105`; `DECISIONS.md:1612,1618`).
  - The "every variant scene" row therefore fails on `mine.tscn`, while §2.1 / DECISIONS say `mine.tscn` keeps "the same
    numbers".
- **Fix:** give HOMING its own numbers (e.g. warning 0.24, or trigger 84). Either change `mine.tscn`'s authored `warning_time`
  to 0.25 and record it, or assert the PROXIMITY row only through its droppers' configs. Say which, so t2/t3 do not decide it ad
  hoc.

### B4. Refusing the Boost Drive in `try_activate()` burns a boost tank on every refused press (t5, t6)

- **Checked:** `open_space/scenes/entities/player/player_ship.gd:403-416`. The Open Space Shift path calls
  `drive.can_activate()`, then `_boost_meter.try_spend_tank()`, then `drive.try_activate(self)`.
  - The comment there makes the order part of the contract.
  - `global/ship_modules/engine_boost_module.gd:50-55` says `can_activate()` is kept "in lockstep" with `try_activate()`'s guards,
    "so a tank is never spent on a press try_activate() would have refused".
- **Problem:** §2.5 says Boost Drive "`try_activate` refuses below the floor". `can_activate()` takes no player argument, so it
  cannot see `boost_efficiency()`. An EMP'd or 0.9-disrupted Shift press would therefore spend a tank and do nothing.
- **Fix:**
  - Check `boost_efficiency() >= MIN_BOOST_EFFICIENCY` in `_step_boost` *before* `try_spend_tank()`, keeping `can_activate()`'s
    lockstep comment true.
  - Keep the check in `try_activate` for the Assault H path (`player_fighter.gd:131-137`).
  - Add a row: a refused Boost Drive press spends no tank and does not change the meter.
  - Also decide whether the Warp module's dash replacement (`dash_state.gd:47-50`, `warp_module_active`) is refused under
    disruption or EMP. Today the plan leaves it as a bypass.

### B5. The hub Mine Layer anchor silently violates Phase 6's tactical-space clearance rule (t13)

- **Checked:** Ph6 plan §2.16 (`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md:710-712`). For every patrol group and every
  element of the space, `distance(anchor, centre) − radius − idle offset − perceive_radius > 100 px`. It is enforced by
  `tests/integration/test_sector_hub_patrol.gd:763` over `_patrol_groups()` (`:720`) and `_space_elements()`.
- **Problem:** the plan puts the Mine Layer at (2600, 0) with idle 160 + perceive 650, so it needs more than 910 px.
  - `TacticalSpace/StructureSatellite` (`sector_hub.tscn:105`, (2588, 887)) is **887 px** away, before its radius.
  - The plan's own minefield at (3300, 560) is **896 px** away, before its 200 + 80 radius.
  - §2.13 adds neither the layer to `_patrol_groups()` nor a `Minefield` case to `_element_radius()` (`:743`), which returns 0
    for unknown nodes. So the existing sweep stays green while the rule is broken. That is a silent contradiction of a recorded
    decision.
- **Fix:**
  - Add the Mine Layer to `_patrol_groups()`.
  - Give `_element_radius()` a `Minefield` case (`radius + trigger_radius`).
  - Move the anchor to a legal place. For example, bearing −22.5° on the 2600 px ring gives (2402, −995): 1891 px from the
    satellite, 1115 px from the Missile Corvette anchor and 1343 px from the Gatling. Let the sweep confirm it.

---

## Minor findings

### M1. t1's named sources of gate time are mostly already on the 8× clock; the real ones are elsewhere (t1)

- **Already fast:**
  - `test_wreck.gd` calls `_scale_clock()` 23 times.
  - `test_enemy_ordnance.gd` scales in `before_each` (`:38-39`).
  - `test_bomber.gd` scales its real-physics rows (`:740`, `:820`).
  - `test_player_hazards.gd` has no `await`; `test_hazard_projectiles.gd` has one.
- **Measured per-file time (this run):** the 1× real-physics files are:
  - `test_armor_query.gd` 5.3 s;
  - `test_station_laser_phase.gd` 4.9 s;
  - `test_station_assault_section.gd` 4.1 s;
  - `test_swarm_drone.gd` 3.6 s;
  - `test_station_incoming_damage_paths.gd` 2.7 s.

  Together that is ≈ 20.6 s, of which roughly 12-15 s can be recovered at 8×. Two caveats: some station rows use
  `wait_seconds(0.1)`-scale tolerances that rule 1 keeps at a lower multiplier, and the station family asserts intent. Another
  candidate is computing the exit probe once: `test_engagement_deadline.gd` is 6.1 s and `test_level1_specialist_spawns.gd`
  is 4.6 s, and both run `SpecialistExitProbe`.
- **The fourth "rule":** "a behaviour-identical speed-up of a hot production path" (the fighter tick) is not one of
  `tests/README.md`'s three rules. It changes production code that `test_fighter_squad.gd` pins by float-sensitive outputs.
- **The floor:** an 8 s floor gives ≤ 236 s, against the ±3 s run-to-run spread of `test_fighter_squad.gd` (README) and the
  240 s ceiling.
- **Fix:**
  - Point t1 at the measured list above.
  - Make the production speed-up a last resort with bit-identical outputs, and record it as a rules change.
  - Either make 12 s hard, or cut the allotments if t1 lands under 12 s.

### M2. `drop_mine` overwrites PULSE / EMP blast damage with the config's 30 (t9, t10)

§2.9 says `drop_mine` "applies the config's mine numbers": blast radius 48 and blast damage 30. DECISIONS says "a dropper
overrides … blast". The PULSE mine's designed `blast_damage` 8 (§2.5) therefore becomes 30 when the layer drops it, and the EMP
mine's 0 would become 30 if its weight were raised. State that the dropper overrides only trigger / arm / warning (and life),
and that blast numbers stay per variant scene. Or give the config per-variant blast fields.

### M3. Undeclared deviations from the Ph4 wall rule (t10)

- **The cap:** Ph4 caps only `c`: `t_wall = t_approach_left + min(c, mine_horizon)` (`DECISIONS.md:1625`, "Only `c` is capped").
  §2.10 caps the sum, `min(t_arrive + (L/2)/lay_speed + arm, lead_horizon)`, yet calls it "the Ph4 wall rule".
  - Numerically it still works, because the plan freezes within 200 px of S, where `t_arrive` is ≈ 0.8 s. But it is a deviation
    and should be stated.
- **The drop point:** "dropped when the arc length passes its rest point *minus* the eject lead" (the Bomber's rule) is the
  opposite of `bomber_brain.gd:754` (`s >= rest_s + eject`).
- **Pass spacing:** DECISIONS says "Passes are 6–9 s apart", but §2.10 uses a 5–7 s REPOSITION period and asserts "≥ 5 s apart".
  Make these agree.

### M4. `test_wreck.gd`'s "no hurtbox larger than its body" rule is a hand list, not a sweep (t9)

`tests/integration/test_wreck.gd:33-44` (`_SHIP_SCENES`) is hand-maintained. §2.9 says the rule "picks it up". It does not: t9
must add `mine_layer.tscn` to the list explicitly. Name it in §2.9's roster list.

### M5. Tasks advertised as parallel edit the same files; one handoff has no owner (t3–t8, t11, t12, t14)

- **Shared files:**
  - t3, t4 and t5, then t6, all edit `enemy_mine.gd` (one `match variant`), `enemy_mine_scenes.gd`, `test_enemy_mines.gd` and
    `test_enemy_bullet_lifetime.gd`.
  - t11, t12 and t14 all edit `test_mine_layer.gd`, and t11 and t12 both edit `mine_layer_brain.gd`.
  - CLAUDE.md allows no worktrees, and §3 line 699 invites running these in parallel.
- **Fix:** chain them in `dependsOn`, e.g. t3 → t4 → t5 and t12 → t11 → t14. The cost is wall-clock only.
- **Beacon handoff:** t7 wires the beacon "if t8 has landed", and t8 uses a placeholder "until t7 if needed". With no ordering,
  nobody owns the final wiring. Add t8 to t7's `dependsOn`.
- **planSections:** t6 lists 2.1 / 2.5 / 2.6 but not 2.2, where the shared trigger / arm / warning numbers its EMP mine scene
  needs are defined. Add "2.2".

### M6. Factual slips the build agents will trip on

- **Deep Space peak:** it is **7 at 15.50 s**, not 6 (S11). This is from the gate's own output in this run. The 16.0 s Mine
  Layer therefore lands at that peak (8 ≤ 12.5, still legal).
- **No UID:** `mine.tscn` has no UID (`mine.tscn:1`), so "keeps its path and UID" means "keeps its path".
- **Wrong property:** `TargetInfo` has `.position`, not `.global_position` (`global/enemy_ai/target_info.gd:17`; §2.3).
- **Plate hierarchy:** the hurtbox is at `Plates/PlateX/HurtBox` (`ram_corvette.tscn:123`). Walking two levels up from the area
  reaches `Plates`, so the stated outcome (rejected) is right but the description ("a plate's owner is `Plates`") is not.

### M7. No research artefacts; many new numbers have no stated origin (t15)

The plan makes no genre claims, and most of its numbers are inherited from earlier phases, so the missing `1-context.md` /
`2-research.md` is acceptable. Several new numbers are invented, though:
- pass 720 / 560;
- spacing, amplitude and arc;
- disruption 0.6 for 2.5 s; EMP 2 s;
- homing 75 / 260 / 380 / 900;
- chain 150 / 0.2.

B2 shows that untested geometry slipped through. Mark these explicitly as starting values with their derivation. Have t15's
`SOURCES.md` state "internal precedents only; no external research" rather than reconstruct sources after the fact.

Two smaller gaps:
- **Hub drifting mines:** §2.13's field weights `w_drifting` 0.15 but sets no `drift_direction`, which defaults to zero, so those
  "drifting" mines are still.
- **Standalone mines:** the epic's "standalone mines" only exist as an AUTHORED field with one child. A bare `EnemyMine` placed in
  a scene never `launch()`es, so it never arms or registers. Say so in §2.8.

### M8. t5 is cross-cutting player work in both modes (t5)

t5 touches:
- `PlayerBase` and both ship classes;
- the contract-heavy `_step_boost`, `EngineBoostModule` and `DashState`;
- `BoostBar` and a ring visual on two ships;
- a new mine variant and a new dual-player test file.

With B4 it carries a real contract risk. Mark it `large`, or split the player hook from the pulse mine.

---

## Verified as correct

- **`EnemyOrdnance`** (`enemy_ordnance.gd`):
  - `Kind.MINE`, eject decay, polled trigger (`_player_in_range` at `:212`), `mine_life` fizzle (`:202`), `_mark_done` latch,
    `hazard_pull_scale()` 0 for mines (`:162`).
  - `_RESET_PROPS` is a `const`, so an overridable `_reset_props()` is needed, as planned.
  - `EnemyOrdnanceScenes.MINE` / `pool_size_for`.
- **Bomber drop:** `Bomber.drop()` is the single configuring call (`bomber.gd:69-97`).
- **`BulletPool`:**
  - `persist_after_owner_death` hand-over (`bullet_pool.gd:23-29, 135-150`).
  - Idle pooled bullets are in the tree with `PROCESS_MODE_DISABLED` (`:66-71`), so launch-scoped registration is justified.
- **`ContactBlast`:** layer 256, player only (`contact_blast.gd:9-10`).
- **`Hazards`:**
  - `pulse_damage` hits both groups by centre distance and bypasses shields (`hazards.gd:104-123`).
  - `around()` includes `info.radius`, so the chain's extra centre-distance filter is needed, as the plan says.
  - `unregister` tolerates a missing node.
- **`HazardInfo`:** has `kind`, `avoid_weight`, `velocity`, `source` and `line_of_sight_blocker`.
- **`ProjectileLifetime`:** `max_time` 0 disables the time rule; `use_world_rect` defaults to true.
- **Player boost and dash:**
  - `OpenSpacePlayerShip._step_boost` / `boost_exit_speed` / `hazard_speed_factor()` (`player_ship.gd:380-464`;
    `player_base.gd:153`).
  - `EngineBoostModule._BOOST_SPEED` / `can_activate` / `try_activate`.
  - `DashState.dash_speed` and the hazard factor in `process_physics`.
  - `BoostBar.setup(meter)`.
  - No existing player EMP hook (only the player's `EMPBlastModule`).
- **Hub:**
  - `SectorHub._spawn_patrol()` has exactly 14 draws (`sector_hub.gd:65-81`, "draws 13 and 14").
  - The anchors are as stated, the Gatling's at (1500, 0), and the nearest-anchor distance of 1100 px is correct.
  - `TacticalSpace` positions are as in `sector_hub.tscn:90-121`.
- **Level 1:** has 16.0 s (deep_space) and 47.0 s (planet_approach) waves in DURATION sections. Planet Approach peaks at 7 / 7.5
  at 98.0 s.
- **Planet Approach headroom:** I hand-checked the 47 s Mine Layer window against the gate's printed lives. Over 47–66 s the
  count stays at 5–6, plus the layer, which is ≤ 7.5.
- **Lives:** sniper 16.23 s, bomber 18.38 s, ram 10.19 s, corvette 16.89 s, support 13.58 s.
- **Test helpers:**
  - `SpecialistExitProbe.worst_disengage` / `corridor_starts`, `level1_slice_replay.gd`, `enemy_ai_harness.gd`,
    `fixture_enemy`.
  - `_scale_clock` / `_restore_clock` in `test_level1_drone_exit.gd`.
  - `EnemyRocketScenes.export_of`.
- **Engine and AI classes:**
  - `EnemyWorld.arena/view_rect/projectile_world_rect`, `AnchorIdle`, `RailTrail`, `StateLight`, `ContactProfile`,
    `AssaultCorridorConstraint`.
  - `EnemyBrain.on_suspended` / `accepts_tow`, `EnemyMover.break_contact(threat_pos, threat_vel, side, speed)`, and the mover's
    "boost bypasses avoidance" rule.
- **Wreck precedent:** Assault drift of 60 px/s and a 40 s life (`wreck.gd:46-49`). The race mine is
  `assault/scenes/race/track/mine.gd`.
- **Gate time:** GUT is 216.4 s with 2139 tests, the same as §2.15's 216.3 s and the slowest-file list.
- **Scope:** the §6.3 / §6.9 / §11.4 / §18.6 / §21–23 / §40 coverage table is complete. The out-of-scope items (EMP on enemies,
  placed Assault fields, difficulty, audio) are each given a reason and an owner phase.
- **Conventions:** composition, a flat config with `privatise()`, design-unit spawns, one owner per mine, the single mover
  writer, signal arity, verbose-gated logs and no hand-typed UIDs are all respected in the design.
- **planSections:** every heading named in `tasks.json` exists in `3-plan.md`. Apart from M5's t6 gap, each task's sections
  carry the numbers and test rows it needs.
- **Complexities:** t2 and t10 as `large` are right.

---

# Plan review: Enemy rework phase 7 (mines, minefields, Mine Layer), round 2

VERDICT: CHANGES_REQUESTED

I reviewed revision 2 of `3-plan.md` and the regenerated `tasks.json` against the code on `agent/auto-dev` @ `daa32bd`. Only
docs have changed since round 1, so round 1's GUT measurement (216.4 s, 2139 tests) still stands and I did not re-run the suite.
I re-ran the numbers myself, using scripts in `/tmp` only:
- `Steering.context_avoid()` against the new 140 px / weight 1.0 footprint (single mine, 9-mine ring, 6-mine laid line, and an
  acceleration-limited mover);
- the pass geometry, plus a pure-pursuit tracking simulation of LAY with the mover's 420 px/s² acceleration limit;
- the hub clearance, from the real `sector_hub.tscn` positions and the shipped configs, applying `test_sector_hub_patrol.gd`'s formula.

All 13 round-1 findings are resolved. The revision also introduces or exposes two blocking problems:
- **N1:** LAY has no run-in, so the "sideways" and "stays on its path" rows fail whenever the layer reaches S from the side.
  This is measured.
- **N2:** the Mine Layer shell task needs mine scenes that three later tasks create, but it depends only on t2 and is advertised
  as parallel with them.

Both are plan / `tasks.json` edits, not a redesign. There are also nine minor findings.

## Round-1 findings

| # | Status | Evidence |
|---|---|---|
| B1 avoidance | **Resolved** | I reproduced §2.3's table to within 1 px. Single mine, margin 24, 200 px/s: 0.6 → 90 / 99 / 109, 0.8 → 153 / 153 / 156. Ring: 0.8 → 155 / 155 / 159 / 162. Laid line: 0.6 → 63–83, 0.8 → 150–154. With a 400–800 px/s² acceleration limit: 0.8 → ≥ 156. The pure-stage (≥ 85 / ≥ 145), field (≥ 140) and layer (> 100) rows all have margin. The restated promise matches the shipped `hazard_avoidance` values (Fighter / Gatling 0.8; Sniper / Razor / Swarm / Support 1.0; Bomber 0.6; Missile Corvette 0.7; Ram 0.5). |
| B2 zig-zag | **Resolved as geometry** (but see N1) | Vertices step 100 at ±35: chord √(100² + 70²) = 122.07 at 35.0°. The ARC offsets are 0 / 70.4 / 105.6, with chords 122.3 / 106.0 / 100. Path lengths are 732.4 and 656.6 (simulated). The three rows now agree with each other. |
| B3 warning rule | **Resolved** | 128 / 0.25 = 512 ≥ 500 (HOMING at 60) and ≥ 475 (DRIFTING). `mine.tscn` goes 0.5 → 0.25, and only `bomber.gd:84` writes `warning_time`. The reset row at `test_enemy_ordnance.gd:431-441` reads the authored value dynamically, so it is unaffected. |
| B4 Boost Drive tank | **Resolved** | The efficiency check goes into the `if drive != null:` condition before `try_spend_tank()` (`player_ship.gd:405-416`). Because the default branch is that `if`'s `elif`, a refused Drive press cannot fall into it. The default press checks before the meter. `try_activate` keeps a guard for the H path (`player_fighter.gd:137`). The warp is covered. "No tank spent" rows exist for both. |
| B5 hub clearance | **Resolved** | The anchor is (2402.1, −995.0). Satellite: 1891 − 28 − 810 = 1053. Minefield: 1796 − 280 − 810 = 706. Anchor spacing: Missile Corvette 1114, Gatling 1343. The minefield against Gatling / Bomber / Missile Corvette gives 895 / 1114 / 1580. The well-edge gap is 48.7 px. The layer joins `_patrol_groups()` and `Minefield` joins `_element_radius()`. See N5 for the leash. |
| M1 gate-time sources | Resolved | §2.17 names the measured 1× files. The production speed-up is a last resort. 12 s is a hard floor with ESCALATE. Allotments total 28.0 s, so the phase ends at 232.4 s. |
| M2 drop overwrites damage | Resolved | `drop_mine` sets only arm, eject and life. The "PULSE stays 8" row exists. |
| M3 wall-rule departures | Resolved | Only `c` is capped. The drop uses the "plus" rule (`bomber_brain.gd:754`, `s >= rest_s + eject`). The DECISIONS Phase 7 section was rewritten, and "6–9 s" is marked as superseded. |
| M4 `_SHIP_SCENES` | Resolved | It is named in §2.11 and in t10. |
| M5 collisions / handoff | Resolved as asked | The mine tasks are chained t2 → t3 → t4 → t6 → t7 → t8 → t9. The beacon belongs to t9. t6 lists 2.2. **But see N2**: the shell's dependency was not chained. |
| M6 factual slips | Resolved | Peak 7 at 15.50 s, no UID, `TargetInfo.position`, and the ALL filter checks `get_parent()`. |
| M7 provenance | Resolved | §2.18 gives an origin for every number. The hub drifters get a seeded direction and a 120 px leash. `placed` lets a lone mine work. |
| M8 t5 size | Resolved | The player hook (large) is split from the pulse mine (small, t6) and the EMP mine (medium, t7). |

Round 1's "no research artefacts" acceptance still holds. The plan makes no genre claims; §1.1 and §2.18 state that no external
research was done.

## New findings

### N1 (blocking, t11). LAY starts wherever APPROACH happens to arrive, so "within 40° of ±u" and "within 40 px of the polyline" fail

**What I checked:**
- §2.12 APPROACH is "seek S at `max_speed`; frozen once within `commit_distance` 200 of S, then LAY".
- The LAY path starts at S, with only a 50 px lead-in before mine 0.
- S is "the end nearer the layer". That fixes which side of C the layer is on, but not the direction it arrives from. In Open
  Space the layer reaches S from wherever REPOSITION left it. In Assault it comes in diagonally from its side spawn.

**Simulation.** Pure pursuit, 60 px look-ahead, 170 px/s, `acceleration` 420. The table shows the maximum velocity angle to u
during LAY, and the maximum distance from the polyline.

| Arrival at S | ZIGZAG | ARC |
|---|---|---|
| along u (aligned) | 29° / 22 px | 33° / 12 px |
| 45° to u at 240 px/s | **49°** / 19 px | **44°** / 28 px |
| perpendicular at 240 px/s | **89° / 45–71 px** | **89° / 72–73 px** |

Even after the lead-in, a perpendicular arrival is still at 44–58° from u.

**Rows that fail as written:**
- §2.12 "Sideways: during LAY … within 40° of ±u";
- "Stays on its path: … within 40 px of the polyline";
- t11's acceptance criteria.

The "pure pursuit … never overshoots past the segment angle" claim holds only for an aligned entry.

**Fix:**
- APPROACH seeks a run-in point `R = S − u·run_in` (starting value 150 px; that is a new config field), then flies R → S along u.
- LAY (and the rows) begin at S.
- `t_approach_left` uses `|R − pos| / max_speed + run_in / lay_speed`.
- With a 150 px run-in I measured ≤ 33° and ≤ 23 px from S onward, even for a perpendicular arrival at R.
- The stall guard and the level-1 life are unchanged if the run-in stays in APPROACH.

Alternatively, scope both rows to "from mine 1 on" and accept a non-sideways first chord. The run-in is better, because the
idea asks for a sideways flight.

### N2 (blocking, t10). The shell task needs the HOMING, CHAIN and PULSE scenes but depends only on t2

**What the shell needs:**
- §2.11 builds `ChainPool`, `PulsePool` and `HomingPool` (the config weights are 0.2 / 0.15 / 0.15). It gates every pool equal to
  `pool_size_for()`.
- It asserts "after `drop_mine` … PULSE is 8" and "an exhausted CHAIN pool falls back to PROXIMITY".
- t10's acceptance criteria repeat both.

**Where those scenes come from:** `homing_mine.tscn` (t3), `chain_mine.tscn` (t4) and `pulse_mine.tscn` (t6).

**The conflict:**
- `tasks.json` has t10 depending on `["t2"]`.
- §3 says "t10 with t3–t9" can run side by side.
- So t10 can start before any of those scenes exist. Its agent would either fail its own rows or create the scenes, colliding
  with t3, t4 and t6 on `enemy_mine.gd`, `enemy_mine_scenes.gd` and the scene files.

**Fix:** set t10 `dependsOn: ["t6"]` (t6 already pulls in t2–t5 transitively), and change §3 to "t10 with t7–t9". t11's
`["t10","t6"]` then simplifies to `["t10"]`. The critical path does not change, because t11 already waits for t6.

### N3 (minor, t11). The spread rotation cannot reach 380 px for a standing player, and the "Gradual" row contradicts its own fallback

- **The geometry:** for a standing player C sits at `fence_distance` 320 from P. Rotating C about P by 40° moves it only
  2·320·sin 20° = 219 px. 380 px needs at least 72.9° (80° gives 411).
- **The cap makes it worse:** with the cap at 18, three earlier passes are usually alive when a fourth is planned. With
  candidates restricted to ±40 / ±80° of the layer's bearing, often none is legal, and §2.12 says "the plan proceeds".
- **The row:** "no two pass centres closer than 380 px while both have live mines" then fails in exactly the hub case (a player
  loitering). It passes only if the unspecified 60 s scenario uses a fast-moving stub, and then it tests nothing about spread.
- **Fix:**
  - Rotate by `2·asin(min(1, (min_pass_separation + 10) / (2·|C − P|)))` per try, alternating sides.
  - Specify the scenario (a standing stub, plus a stub moving at 220 px/s).
  - Assert ≥ 380 px only for plans that did not take the fallback, and add a `spread_fallbacks` seam that the standing scenario
    reports.

### N4 (minor, t2 / t8). `fixture_enemy.tscn`'s `HurtBox` has no `CollisionShape2D`

- `tests/helpers/fixture_enemy.tscn:26-29` is a bare `Area2D` on layer 512. An ALL mine's `ProximityArea` poll
  (`get_overlapping_areas()`) can therefore never see it.
- So t2's "an ALL mine is set off by a `fixture_enemy` sitting inside the trigger radius" cannot pass as specified.
- §2.10 mentions a "fixture hurtbox radius 14", but t2 is not given §2.10.
- **Fix:** in §2.1, next to the existing `add_to_group("enemies")` note, state that the hostility rows add a 14 px `CircleShape2D`
  to the fixture's `HurtBox` (the fixture ships without one). The same applies to t8's field rows.

### N5 (minor, t14). `_element_radius()` for `Minefield` ignores the drift leash, and `Minefield` has no `trigger_radius`

- The hub field has `w_drifting` 0.15 and `drift_leash` 120 (§2.15). Its drifters therefore reach 200 + 120 + 80 = 400 px from the
  field centre, not 280.
- §2.10's exports also include no `trigger_radius`, so `radius + trigger_radius` will not compile as written.
- With 400 the clearances are still legal: Mine Layer 586, Gatling 775 (computed).
- **Fix:** `radius + (drift_leash if w_drifting > 0 else 0) + EnemyMineScenes.export_of(PROXIMITY, &"trigger_radius", 80.0)`.

### N6 (minor, t8). AUTHORED mines run `_ready()` before `Minefield._ready()`

- Godot readies children first. An editor-placed `EnemyMine` under `Mines` therefore runs its `placed` setup (`expired ->
  queue_free`, backstop 0, the deferred `launch`) before the field sets `placed` and `hostility` on it.
- §2.1 does that setup in the mine's `_ready()`.
- **Fix:** say that AUTHORED children must be authored with `placed = true` and the field's hostility (and the field asserts it),
  or move the mine's placed setup into its deferred launch call so that it sees the field's values.

### N7 (minor, t5). The disrupted Boost Drive and dash drop below cruise, against the plan's own principle

- **Boost Drive:** §2.6 scales the Drive's burst "× efficiency". At 0.4 the burst eases from 600 px/s to `_BOOST_END_SPEED` 500 ×
  0.4 = **200 px/s**, below the 420 cruise, with thrust locked out (`engine_boost_active`).
- **Dash:** the disrupted dash is 350 × 0.4 = **140 px/s**, below `DashState.move_speed` 180, under a movement lock.
- **The contradiction:** the Shift boost deliberately scales only the excess over `max_speed`, and §5 lists "disrupted boost slower
  than cruise" as a mitigated risk. A disrupted Drive press or dash is now a net slow-down.
- **Fix:** use the same excess-over-cruise form for both Drive speeds (floored at the ship's `max_speed`) and for the dash (floored
  at `move_speed`). Otherwise state that the slow-down is deliberate and adjust the rows.

### N8 (minor, t2 / t11). Two rows are ambiguous enough to be built wrong

- **Real-mover row (§2.3):** it does not fix the lateral offset. Head-on passes (0.8 gives 153 ≥ 120 and ≥ 0 + 100). At lateral
  60 it fails, because 156 < 60 + 100. Specify head-on.
- **Hazard-aware layer row (§2.12):** "every live mine of its earlier passes, while not in LAY" must exclude the pass the layer is
  breaking off from during BREAK_OFF. At the end of LAY the centre is ≈ 61 px from mine 5. Also say that tail-drop mines are
  excluded.

### N9 (minor, t12 / t15). The lose-radius claim, the persistence row and the exit probe

- **The lose-radius claim:** §2.14 says the inequality (1212 < 1500) means "the layer's own cycle never sends it home mid-fight".
  The APPROACH lead is not in it.
  - Against a player cruising at 420 px/s, the layer at S at freeze time is about √((420·3.09 + 260)² + 300²) ≈ 1587 px from P.
  - The layer (240 px/s) cannot get ahead of a player cruising at 420 px/s anyway.
  - Restate the claim as "for a player at ≤ 220 px/s".
- **The persistence row:** "flies 1600 px away and the layer returns home" needs the stub moved beyond `lose_radius` *of the layer*
  (`AnchorIdle._within` is actor-to-target). A layer in REPOSITION orbits and follows the player. Say that the stub is teleported.
- **The exit probe:** `SpecialistExitProbe.disengage_seconds()` enters DISENGAGE with no planned pass, so §2.12's "continue along u"
  is undefined there. State the fallback (the current heading, as §2.11's shell says) so that t15's measured exit is the real one.

### N10 (minor, t2). The pre-approved levers cover only "a level-1 gate"

t2's acceptance also requires every `test_bomber.gd` / `test_enemy_ordnance.gd` row to stay green unchanged. Bomber mines become
140 px hazards that a 0.6 Bomber now avoids, including its own mines when it turns. Extend the two levers (pad 0, then no
registration, on `mine.tscn` only) to any existing row that turns red because of the registration, reported the same way.

### N11 (minor, t16). The docs task is `small`

t16 has to:
- run the `updating-project-docs` sweep over about ten docs;
- write the three-file dossier;
- write the as-built section;
- reconcile every deviation recorded by t1–t15.

Phase 6's equivalent (t19) was `medium`. Make t16 `medium`.

## Verified as correct (round 2)

- **`planSections`:** every heading listed in `tasks.json` exists. With the For-every-task section, each task can be built from its
  own sections, apart from N4's fixture note for t2.
- **Complexities:** t2, t5 and t11 are large (t11 at `xhigh`). The remaining tasks are fine apart from N11.
- **Pooled registration:** `BulletPool.acquire()` reparents synchronously before `reset()` and the caller's `launch()`
  (`bullet_pool.gd:80-94`). Launch-scoped registration therefore survives the reparent, and `_exit_tree` unregistration on recycle
  is correct.
- **Open Space lifetimes:** Open Space has no projectile world rect (`ProjectileLifetime` header; `EnemyWorld.projectile_world_rect`).
  Persistent Open Space mines and the hub field are therefore not culled; only `max_time` applies.
- **Mines as hazards:**
  - `Hazards.bend_heading` returns the heading unchanged for a zero pull, so live mines do not disturb rockets or bombs.
  - `test_enemy_ordnance.gd:674` (`Hazards.count() == 0` after a mine burst) holds, because detonation unregisters.
  - `test_sector_hub_patrol.gd:547` holds if the field lives under `TacticalSpace`, as planned.
- **ALL filter:** only the Ram's plate hurtboxes are not direct root children (`ram_corvette.tscn:123,146,170`). All 12 enemy
  scripts join `enemies` in their own code.
- **Level 1:**
  - The 16.0 s and 47.0 s waves exist in DURATION sections. Planet Approach is 110 s.
  - The station section (the next ENEMIES_CLEARED section) starts after the 30 s asteroid section. The deep-space layer's life plus
    9 s of mine life ends by about 46 s.
  - Planet Approach stays at 5–6 specialists plus the layer through about 68 s.
- **Gate arithmetic:** the allotments sum to 28.0 s; 216.4 − 12 + 28 = 232.4 s ≤ 240. The t1 floor and the ESCALATE path are
  credible.
- **Coverage:** the IDEAS §6.3 / §6.9 / §11.4 / §18.6 / §21–23 / §40 coverage is complete, and nothing is dropped without a reason.

---

# Plan review: Enemy rework phase 7 (mines, minefields, Mine Layer), round 3

VERDICT: CHANGES_REQUESTED

Reviewed Revision 3 (commit `3bd53b2`) of `3-plan.md`, `tasks.json` and the Phase 7 section of `DECISIONS.md`, against the code on `agent/auto-dev`. An independent
general-purpose subagent did the review. It re-simulated the geometry in node (`/tmp/rv3/runin.js`, `standing.js`, `moving.js`, `arrival.js`), modelling the mover on
`global/enemy_ai/enemy_mover.gd:215-247`: velocity is `move_toward(desired, 420·dt)`, `max_speed` 240, and the turn rate limits only the facing. The coordinating agent
re-derived both blocking findings by hand from 3-plan.md:684-739 and confirmed them. No repo file outside this directory was modified.

## Summary

Revision 3 resolves all 11 round-2 findings, and none of the 13 round-1 findings has come back. The run-in, the spread rotation, the disruption floors, the clearance
radii and the lose-radius numbers all check out against the code and in simulation.

Two blocking problems remain, both in how the Mine Layer's APPROACH plans and freezes a pass in Open Space. Neither was caught in earlier rounds: the round-2 simulation
covered LAY tracking from R onward, not whether APPROACH ever freezes.
- **F1:** against a standing player the plan never freezes.
- **F2:** against a moving player above about 150 px/s it almost never converges, so the t11 give-up control row cannot pass.

Both are edits to §2.12, §2.18, the owner summary and t11's criteria. Neither needs a redesign. There are also four minor findings.

## Round-2 findings

| # | Status | Evidence |
|---|---|---|
| N1 run-in | Resolved (spec gap: F3) | The handover happens within 10–60 px of R, then LAY runs from S. ZIGZAG reaches at most 32.1° / 19.1 px and ARC at most 32.7° / 16.0 px, for aligned, ±perpendicular (300 px, 240 px/s) and 45° arrivals. A U-turn arrival stays within 31° / 31 px. |
| N2 t10 dependencies | Resolved | t10 `dependsOn ["t6"]`, t11 `["t10"]`, and §3 says "t10 with t7–t9". |
| N3 spread | Resolved for a standing player (moving player: F4) | θ = 2·asin(390/640) = 75.09°. +2θ is 390 / 618 / 591 px from the centres at ±75.1° / 0°. The fallback fires when no candidate is legal. |
| N4 fixture shape | Resolved | Stated in *For every task*, §2.1, §2.10, and the t2 and t8 descriptions. |
| N5 clearance radius | Resolved | 1795.6 − 400 − 810 = 585.6 px. The formula fits `test_sector_hub_patrol.gd:743-780`, and the 400 px radius does not collide with the `e[1] == 420.0` well filter (line 818). |
| N6 ready order | Resolved | Deferred `_start_if_placed()`, the mask set in `launch()`, and ready-order rows in t2 and t8. Its `mine_life` side is F5. |
| N7 floors | Resolved | Read from the code: `boost_exit_speed` 700 (`player_ship.gd:18`), `_BOOST_SPEED` 1500 / `_BOOST_END_SPEED` 500 (`engine_boost_module.gd:11-12`), and MoveState 360 / DashState 180 / 350. These give 532, 852 / 452, 816 / 416 and 248. |
| N8 ambiguous rows | Resolved | The real-mover row is head-on. The "keeps clear" row excludes the current pass, LAY, BREAK_OFF and the tail-drop mines. |
| N9 lose radius / persistence / probe | Resolved | 1421.5 < 1500. Both rows teleport the stub, and the no-pass DISENGAGE heading is specified. |
| N10 levers | Resolved | They cover any existing row, checked by re-running it with `registers_hazard = false`. |
| N11 t16 size | Resolved | t16 is medium. |

**Other checks**
- **Round-1 B1–B5 and M1–M8:** still resolved. Revision 3 changed none of the measured numbers.
- **Allotments:** they total 28.5 s, so the phase ends at or below 216.4 − 12 + 28.5 = 232.9 s, under 240 s.
- **`planSections`:** every task's section numbers map to exactly one heading in 3-plan.md (scripted check). Each task can be built from *For every task* plus its
  listed sections; F1–F4 all land in §2.12, which t11 already lists.

## New findings

### F1 (blocking, t11). Against a standing player, APPROACH never freezes its plan

**Checked:** 3-plan.md:686 (for |v̄| < 60, f is the unit vector from P toward the layer), :688 (re-planned every tick until frozen), :715 (standing C = P + f·320),
:729 (frozen within `commit_distance` 200 of R), and :998 (`approach_max_seconds` rationale: "≈ 2.2 s to reach R for a standing player").

**Why the plan can never freeze:**
- R = P + 320f − 450u, so R always sits 54.6° of bearing away from the layer's own bearing, 552 px from P.
- Each tick f follows the layer, so as the layer moves toward R, R rotates by the same amount.
- The layer can get no closer to R than 552·sin 54.6° ≈ 450 px, which never reaches the 200 px freeze distance.
- The coordinator confirmed this by hand. The subagent's simulation (four initial velocities, 600 px start) never froze in 12 s; the closest approach to R was 450.1 px,
  and the layer spiralled in to circle the player at about 330 px.

**Consequences:**
- Every pass against a loitering player runs the full 6 s give-up.
- During those 6 s the layer circles through the band where its earlier lines lie (210–440 px from P), which endangers the "hazard-aware > 100 px in APPROACH" row.
- The line rate drops to about one per 20 s, not the summary's 10–14 s.
- `fence_fallbacks` fires on every standing pass, against §1.3 and §2.12's "only for a layer behind a fast player".
- §2.18's 2.2 s premise is false.

**Fix:**
- Latch f (the layer's bearing from P) when APPROACH starts. Keep it until the plan freezes or |v̄| reaches `frame_speed` or above. With f latched, the plan freezes in
  about 1.5 s.
- Add a row: a standing stub with the layer starting at the 600 px standoff freezes within 2.5 s, with `fence_fallbacks` 0.

### F2 (blocking, t11 and the owner summary). Against a 220 px/s player the lead almost never converges, so the give-up control row cannot pass

**Checked:** 3-plan.md:711 (`t_approach_left = |R − pos| / max_speed + …`), :714 (C = P + v̄·t_lead + 260f), :736–739 (give-up described as "behind" only), :782 (lead
row at 220 px/s), :790 (Gradual scenario at 220 px/s), :800–802 (give-up row and its control: layer starting 600 px ahead gives `fence_fallbacks` = 0), and t11's
acceptance criteria.

**Why it diverges:**
- R's distance feeds into t_lead, which pushes R further away.
- Take a 220 px/s player with the layer 600 px ahead. Then x_C ≈ 951 + 0.917·|R − pos|, and |R − pos| ≥ x_C − 600, so a self-consistent R needs |R − pos| ≳ 4.2 km.
  The coordinator derived this by hand.
- Phase 4 hit the same thing with the Bomber. DECISIONS.md:1626 says "a plain fixed-point iteration diverged", and `bomber_brain.gd:441-509` uses an earliest-feasible
  scan capped at `approach_cap` instead. The plan specifies neither.

**Subagent simulation** (re-planned every tick, 420 px/s² acceleration). Time until the plan freezes, for a layer 600 px from the player:

| Player speed (px/s) | Layer ahead | Layer abeam | Layer behind |
|---|---|---|---|
| 60 | 1.33 s | 2.15 s | 5.75 s |
| 100 | 1.53 s | 3.85 s | 8.40 s |
| 150 | 2.90 s | 8.13 s | 15.05 s |
| 180 | 5.35 s | 14.17 s | 24.40 s |
| 200 | 9.28 s | 23.22 s | never (30 s) |
| 220 | **21.37 s** | never (30 s) | never (30 s) |

**Consequences:**
- The control row (220 px/s, layer ahead, expects 0 fallbacks) fails, because the 6 s give-up fires first.
- The lead row ("C > 80 px ahead of a 220 px/s stub when the middle mine arms") only passes with a contrived start that is already frozen.
- The Gradual 220 px/s scenario is all give-ups, so it never tests the lead.
- For the owner: against any player above about 150 px/s (Open Space cruise is 420 px/s), the line is laid between the player and the layer, not across their path. The
  summary does not say this.

**Fix:**
1. Compute the arrival time with the Phase 4 earliest-feasible scan: T in 0.1 s steps up to a cap, then bisect, where the flight time is
   |R(T) − pos| / max_speed + run_in / lay_speed. Do not use a fixed point.
2. When no T within the cap is feasible, go straight to the frozen fence plan. Otherwise, scope the 6 s timer to "no feasible arrival".
3. Move the lead row and the give-up control row to about 100 px/s with the layer ahead, and keep the give-up row itself at 220 px/s. For the Gradual moving scenario,
   either run it at 100–120 px/s, or keep 220 px/s and assert that every plan is a fence plan.
4. State in the owner summary and §5 that a cruising player gets a fence line rather than a line across their path.

### F3 (minor, t11). The handover from "seek R" to the run-in, and what "passes S" means, are not specified

**Checked:** 3-plan.md:728–731 and :785.

**What goes wrong:**
- If the run-in starts as soon as the plan freezes (up to 200 px from R), a perpendicular arrival from the −n̂ side reaches 39.6° (bound 40°), and a freeze from 600 px
  reaches 66°.
- When the layer's projection starts past S (the latched-standing geometry from F1), a "projection ≥ S" test starts LAY immediately, mid-line.

**Fix:** "Seek R until within `path_lookahead` (60 px) of it, then run in. LAY starts when the centre's projection on u *crosses* S from the R side." With this
handover, every case tried stays within 33° and 31 px.

### F4 (minor, t11). Rotating C for a moving player moves the line off the player's track

**Checked:** 3-plan.md:704–707.

**What goes wrong:** for a moving player u stays `v̄.orthogonal()`, and |C − P| is about 1136 px at freeze, so θ ≈ 19.8°. Rotating C about P by θ moves it about 385 px
sideways, which is more than the line's 300 px half-length, so the predicted track misses the line by about 85 px.

**Fix:** apply the rotation only to the standing (fence) form, and for a moving player shift C along f instead. Alternatively, state the miss as intended.

### F5 (minor, t2 / t8 / t14). `mine_life` "0 unless authored" leaves placed PROXIMITY mines fizzling after 8 s

**Checked:** 3-plan.md:40 and :189; `enemy_ordnance/mine.tscn`, which authors `mine_life = 8.0` (also the `enemy_ordnance.gd` default); §2.10:594 ("never fizzles", 60 s
hand-ticked); and the hub field's `w_proximity` 0.4.

**What goes wrong:** read literally, t2 keeps 8 s on every placed PROXIMITY mine. t8's "never fizzles" row then fails, or about 40% of the hub field fizzles 8 s after
load.

**Fix:** placed mode sets `mine_life` from a new export `placed_life` (default 0), or `Minefield` zeroes `mine_life` on its mines. State which in §2.1.

### F6 (minor, t10 / t15). DISENGAGE must release the corridor constraint

**Checked:** §2.11, §2.12:755, `assault_corridor_constraint.gd` (which pushes a ship back in past `hard_band` 450), and the `specialist_exit_probe.gd` header.

**What goes wrong:** without `mover.release_constraint()`, which the Bomber's DISENGAGE calls, an exit along the current heading is capped by the constraint, and the
t15 exit probe measures the cap rather than the exit.

**Fix:** add one line to §2.11: "DISENGAGE calls `mover.release_constraint()`, as the Bomber does."

## Checked and fine

- **Gate time:** the t1 floor (with its ESCALATE path) and the per-task allotments are credible.
- **Spill-over:** the deep_space deadline is 60 s, and the layer at 16 s plus about 15 s of life, its exit and 9 s of mine life fits inside it.
- **Assault R:** it stays at least 24 px inside the view (174 − 150).
- **DECISIONS.md:** its Phase 7 section matches Revision 3.
- **Task chaining:** it matches §3, and no two parallel tasks share a code or test file.

---

# Plan review: Enemy rework phase 7 (mines, minefields, Mine Layer), round 4

VERDICT: APPROVED

Reviewed Revision 4 (commit `75f301b`) of `3-plan.md`, `tasks.json` and the Phase 7 section of `DECISIONS.md`, against the code on `agent/auto-dev`
(`bomber_brain.gd`, `enemy_mover.gd`, `steering.gd`, `enemy_ordnance.gd`, `mine.tscn`, `specialist_exit_probe.gd`). The geometry was re-simulated in node
(`/tmp/rv4/sim.js`, `circle*.js`, `turn.js`), modelling the mover from `enemy_mover.gd:215-247`: velocity `move_toward(desired, 420·dt)`, `max_speed` 240,
60 Hz. The sim implements the §2.12 rules as written: the standing latch, the sign rule, the lead scan with the spin-up term, the fence fallback, the
lost-feasibility guard, the freeze at 200 px, the 60 px handover, the crossing test, and LAY pursuit with the Dispenser "plus" drop rule. No repo file other
than this one was modified.

## Summary

All six round-3 findings are resolved, and the simulation reproduces every number Revision 4 quotes. Nothing from rounds 1–2 has regressed. Nothing blocking
remains. The new findings below are all minor, and all are in t11's planning logic, which an implementing agent can handle. The most important is **G1**:
§2.12 never says how APPROACH steers. Every freeze bound assumes the mover's acceleration limit is the only limit. A Bomber-style turn-limited request fails
three rows from a layer at rest facing away. One sentence in t11's description fixes it.

## Round-3 findings

| # | Status | Evidence |
|---|---|---|
| R1 standing player never freezes | **Resolved** | §2.12:729-734 latches f and the sign at APPROACH start. Sim, standing stub: frozen at 1.67 s from 600 px and 2.52 s from 900 px, at every bearing. R does not move (0 px), and `fence_fallbacks` is 0. Rows at :856-859 and in t11's criteria. |
| R2 moving-player lead diverges | **Resolved** | §2.12:760-779 uses the Bomber's scan shape (`bomber_brain.gd:475-509`). The spin-up term matches `_flight_time()` for d ≥ d_acc (I re-derived it). Sim at 100 px/s: lead plan frozen at 1.52 s from 600 px ahead and 3.83 s abeam (row bounds 2.5 / 5.0). At 220 px/s, from 600 and 900 px at every bearing, the fence fallback is taken on the first tick. C on the track line. C ahead of the live stub when the middle mine arms: 199 px (mine 2) / 138 px (mine 3), against a bound of > 80. The scan is well-posed: d\|R(T) − pos\|/dT ≤ v < `max_speed`, so ft − T is strictly decreasing, the earliest T is unique, and the scan row's "T − 0.004 infeasible" check is valid. The owner summary (line 8) and §5 state that a cruising player gets a fence line. |
| R3 handover / "passes S" | **Resolved** | §2.12:800-803. At the handover the projection lies in [−210, −90], so the crossing is always forward. Sim from S on: ≤ 32° from u and ≤ 21 px from the polyline, at every bearing and speed tried. |
| R4 rotation moves a moving player's line | **Resolved** | Rotation is used only for the fence form (:753-758). The lead form shifts C along f (:772-774). Lead spread row checked: the shifted plan has T ≈ 3.95 s, still feasible, and its C is 550 px from the unshifted C (≥ 380) and on the track. Fence rows checked: +2θ is 390 / 618 / 591 px from the centres at +75.1° / 0° / −75.1°, and with ±2θ also taken, no candidate is legal. |
| R5 placed mines inherit 8 s | **Resolved** | §2.1:211 sets `mine_life = placed_life` always. `launch()` (`enemy_ordnance.gd:141-150`) does not reset `mine_life`, so a value set before the launch holds. Boundary rows are in §2.1:262 and §2.10:620, and in the t2 / t8 / t14 criteria. |
| R6 corridor holds an exiting layer | **Resolved** | §2.11:678-680 and §2.12:827. `BomberBrain._enter_disengage()` does call `release_constraint()` and set `max_speed = exit_speed` (`bomber_brain.gd:868-872`). `EnemyMover.constraint_released()` exists (`enemy_mover.gd:144`). Rows are in t10 and t15. |

**Rounds 1–2:** B1–B5, M1–M8 and N1–N11 are still resolved. Revision 4 changed no measured footprint, warning, disruption-floor, clearance or roster
number. The lose-radius inequality recomputes to 1415.7 < 1500, and the allotments still total 28.5 s (phase ≤ 232.9 s).

## New findings (all minor)

### G1 (minor, t11): APPROACH's steering is unspecified, and the freeze bounds only hold for an un-turn-limited seek

**Checked:** §2.12:799 ("Seek R at `max_speed`"), §1.4:154-156 (the planner's sim "has no turn-rate limit"), `bomber_brain.gd:628-651`. The Bomber requests
`Steering.turn_toward(_heading(), …, max_turn_rate)`, and `_heading()` is the facing at rest. Other brains use `mover.seek()`; 23 `turn_toward` uses across
the brains make both shapes likely.

**Problem:** suppose the layer copies the Bomber and turn-limits its request at `max_turn_rate` 2.4 rad/s, starting at rest with a facing that points away
from R (rows say "at rest" and give no facing; the default nose-down facing is +y). Then it first accelerates the wrong way and loops round. Sim:

| Row | Bound | Worst case, turn-limited |
|---|---|---|
| Standing freeze | ≤ 2.5 s | 3.73 s |
| Lead from ahead | ≤ 2.5 s | 4.67 s |
| Abeam | lead plan ≤ 5.0 s, `fence_fallbacks` 0 | hits the 6 s backstop |

With `mover.seek()` (straight request, acceleration-limited only), every row passes with the quoted margins.

**Fix:** add to §2.12 / t11: "The seek to R and the run-in request the straight direction (`mover.seek()` / `request_velocity(dir·speed)`, no
`Steering.turn_toward`); the mover's `acceleration` is the only limit, as in the simulations." Alternatively, give the rows an initial facing toward R.

### G2 (minor, t11): a frozen plan has no timeout in Open Space, so an unreachable R holds the layer in APPROACH indefinitely

**Checked:** §2.12:808-810 (the backstop counts only "without freezing"), :800 (the handover needs the layer within 60 px of R), `steering.gd:228-330`
(inside a footprint every heading within 112.5° of the centre is danger 1), and §2.3 (avoidance 0.8 keeps ≥ 149 px from a mine). The spread checks only
centre to centre, and no-stacking checks only rest points.

**Problem:** nothing keeps R, which sits 450 px from its own C, away from an older line's mines. If R lies within about 90 px of a live mine, the layer's
own avoidance keeps it out of the 60 px handover disc. It then seeks a frozen R until the player leaves `lose_radius`: no line and no backstop. This is
rare: for a standing player R sits at 552 px from P, outside every fence mine's footprint (≤ 548). For a moving player it is plausible over a long hub
session with up to 18 live mines. No row exercises it.

**Fix:** either or both of:
- Bound the frozen seek too: if LAY has not started within `flight_time(R)` at the freeze + `run_in / lay_speed` + 2 s, abandon to REPOSITION (count it in
  a seam). Do not take the fence fallback, so the standing `fence_fallbacks` 0 rows are unaffected.
- Treat a candidate whose R or S lies within `trigger_radius + hazard_pad + hazard_margin` (164 px) of a live mine as illegal in the spread check.

Add a pure row: a frozen plan with a live mine 50 px from R leaves APPROACH within the bound.

### G3 (minor, t11): for a turning player R moves with the heading, and the spacing row checks a different C from the one spread chose

**Checked:** §2.12:728 (a moving player's f is re-read every tick), :781-782 (the candidate is chosen on the first plan, and later ticks re-run only the
scan), :808-810 ("no scenario in this plan should reach" the backstop), and the Gradual row at :879-886 (120 px/s on a 700 px circle; spacing asserted on
the pass centres).

**Problem:** sim with that scenario's player, the layer starting at the 600 px standoff (8 bearings × 6 circle phases × 3 initial velocities = 144
starts):
- 22 of 144 starts hit the 6 s backstop. R travels 1270–1580 px while the layer chases it. Another 4 starts freeze through the lost-feasibility guard on
  tick 2.
- Where a lead plan froze normally, C moved a median 165 px and up to 931 px between the candidate choice and the freeze. Legality is checked on the
  first plan's C, but the row asserts ≥ 380 px on the pass centre. A drifted C can break the row without counting as a `spread_fallback`.

The row is likely to pass in practice, because consecutive centres on that circle are more than 800 px apart. The design gap and the false claim stand
anyway.

**Fix:**
- Re-check spread legality on the frozen C. If it is now within 380 px of an earlier live centre, increment `spread_fallbacks`. That makes the row's
  exemption cover the drift.
- Restate §2.12:808-810 as "a turning player can reach the backstop", and log `fence_fallbacks` for the moving scenario, as it already does.
- Optional: re-read f only when v̄ has turned more than 30–45° from the latched f (re-choosing the candidate). The sim gives 22 → 12 → 6 backstops for no
  re-latch / 30° / 45°.

### G4 (minor, t11): the "19th drop retires the oldest" boundary may never occur inside a 60 s Gradual scenario

**Checked:** §2.12:886 ("in both" scenarios).

**Problem:** a standing cycle runs about 3.9 s to the first LAY, then 3.9–4.3 s of LAY, 1.2 s of BREAK_OFF, 5–7 s of REPOSITION and 3.9–6 s of APPROACH.
The 19th drop is mine 1 of pass 4, at about 52 s typically and about 60.0 s with the slowest draws. In the moving scenario each backstop (G3) adds 6 s.
With one or two backstops there are only 18 drops in 60 s, so the boundary is never reached. No-stacking skips make it worse.

**Fix:** keep "the live count never exceeds 18" in both scenarios. Move the boundary to its own hand-ticked row: fill the FIFO with 18 live mines, then
drop once and assert that the oldest is retired.

### G5 (minor, t11): no hysteresis on `frame_speed`, and the re-latch rule is ambiguous

**Checked:** §2.12:727-731 and :781-782.

**Problem:**
- Every standing↔moving switch re-latches the frame and re-chooses the candidate. A player whose smoothed speed hovers around 60 px/s (braking to a
  hover, or drifting) therefore keeps resetting R, and the 6 s backstop is the only exit.
- After a standing→moving re-latch, it is unclear whether an infeasible scan takes the fence fallback (as a "first plan") or the lost-feasibility guard
  (because an earlier tick of the same APPROACH had a feasible plan).

**Fix:**
- Add hysteresis, for example moving at ≥ 60 px/s and standing below 45 px/s, or allow at most one re-latch per APPROACH.
- Say which rule applies after a re-latch. Suggested: the guard applies only within one frame, and a re-latched frame's first infeasible scan takes the
  fence fallback.

### G6 (nit, t11 / t16): doc slips

- §1.4:167 says 1414 < 1500, while §2.14:945 and DECISIONS say 1415.8.
- `DECISIONS.md:2473` is a run-on sentence: "…as Ph4's fixed-point iteration did and the drop fires after…" is missing a full stop and its clause.
- The §3 table gives t16 no §1.4, but `tasks.json` lists it. `tasks.json` is the right one.
- §2.12:720 says 100–120 px/s gets a lead plan "from every bearing except behind". The sim gives the fence fallback for 120 px/s with the layer abeam at
  900 px; only 600 px holds. No row depends on it.
- The scan row has to rebuild R(T − 0.004) from the formula. A `run_in_point_at(T)` seam beside `flight_time(point)` would keep the test off a copied
  formula.

## Checked and fine

- **`planSections`:** every listed number (1.1–1.4, 2.1–2.19, 5, 6, 7) is an existing heading. Each task can be built from *For every task* plus its
  sections:
  - t10 has the DISENGAGE release in §2.11.
  - t11's whole planner is in §2.12.
  - t12 / t15 list §2.12 for the brain they extend.
- **Dependencies and parallelism:** unchanged from round 3. No two parallel tasks share a file.
- **t11:** still one large task (`effort` xhigh). It is bigger than in round 3, with two planners, the scan, two guards, about 25 rows and two 60 s
  scenarios, but it is coherent and still within one session. If it overruns, the natural split is geometry, LAY and Assault on one side and Open Space
  planning on the other.
- **Assault R / clamp, spill-over and the level-1 counts:** unchanged and still hold. The deep-space layer at 16 s has about a 6 s heading exit, so it is done
  with its mines by about 46 s.
- **Give-up row:** v̄ is seeded from the first sample, the Bomber's shape (`bomber_brain.gd:277-286`). The 220 px/s stub is therefore "moving" on the first
  tick, and the fence fallback fires on the first planning tick as the row expects.
- **Lose-radius farthest-point argument (§2.14):** sound. R's offset from the player is v·3.147 + 650 along the heading and 450 to the side.
- **Gate time:** the t11 allotment of 4.5 s is plausible. Every new row is hand-ticked, and the scan is at most 61 + 5 cheap evaluations a tick.
