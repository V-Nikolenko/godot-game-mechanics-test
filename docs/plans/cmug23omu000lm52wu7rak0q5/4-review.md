VERDICT: CHANGES_REQUESTED

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
