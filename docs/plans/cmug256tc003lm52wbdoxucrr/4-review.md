VERDICT: CHANGES_REQUESTED

# Plan review, round 1 (epic cmug256tc003lm52wbdoxucrr, Phase 12: Dreadnought hunting boss)

I read `3-plan.md` (revision 1, all 595 lines), `1-context.md`, `2-research.md`, `tasks.json` (t1 to t14), `CLAUDE.md`, `DECISIONS.md` (Phase 10 as built, the Phase 11
planned and as-built sections, and the Phase 12 section the plan stage already appended), the Phase 10 and Phase 11 `REPORT.md`s and `tests/README.md` → *Gate time*. Then I
checked the code each section relies on, on `agent/auto-dev` (HEAD `b92d92b`). I did not run the gate.

The overall design is sound and builds on what Phases 10 and 11 shipped instead of rebuilding it. Two `BossPhaseDriver` tracks give a free destruction order without
touching the driver. `ON_OWN_DESTROYED` is a small, opt-in change to `BossReinforcements` that is called out as a convention change. The torpedo is an `EnemyOrdnance` scene,
the wake is a `HazardField`, the chunks are `DebrisFragment`s, and the escorts go through `BossReinforcements`. Each option table has real tradeoffs. Every `planSections`
heading exists. Four problems are design defects that would cost implementation time or leave a row unsatisfiable, so they block approval.

## Blocking

### B1. The missile-fan rack's tuning has no authoring path (t3, t8)
- **Plan:** §2.8's table, `3-plan.md:357`, gives the rack `ROCKET_BATTERY` with `fan_count` 5, `fan_spread_deg` 40, `salvo_count` 1, `pursuit_chance` 0 and
  `cooldown_seconds` 6.0. The tuning column is headed "(slot / mount scene)", and *For every task* (`:54`) says mount tuning lives "in mount scenes / `TurretMountSlot` exports".
- **Code, part 1:** `TurretMountSlot` (`assault/scenes/enemies/defense_turret/turret_mount_slot.gd`) can only override `variant`, `rest_bearing_deg`, `turn_rate_override`,
  `traverse_deg_override` and `pool_period_factor`.
- **Code, part 2:** `TurretMountScenes.scene_for()` maps each variant to exactly one scene. `ROCKET_BATTERY` is the shared `rocket_battery_mount.tscn`, which authors
  `salvo_count = 2` (`:9`), `pursuit_chance = 0.333` (`:11`) and `cooldown_seconds = 5.5` (`:18`). After t3 it would also author `fan_count` 1.
- **Code, part 3:** `TurretMountBuilder.build()` (`turret_mount_builder.gd:14-38`) sizes every pool from `mount.pool_specs()` at build time. Writing `fan_count` or
  `salvo_count` on the instanced mount afterwards therefore leaves the pools sized for the shared scene's one-wide fan. The Carrier writes cooldown and pursuit after the build,
  but that precedent only works for changes that lengthen the period. The result would be dry pools and silently refused rockets, which is exactly what the Ph11 density rule
  forbids.
- **Fix:** give the fan rack an authoring path that exists before the pools are sized. Two options:
  - Append a variant (for example `MISSILE_FAN`) with its own standalone scene on `rocket_battery_mount.gd`. This follows the `HEAVY_CANNON` precedent (`burst_cannon_mount.gd`
    on its own scene) and the Ph11 "standalone, never inherited" rule.
  - Or add a slot-level override dictionary that the builder applies before `pool_specs()`.
- Put it in t3 and add a pool-size row for the Dreadnought's rack.

### B2. One shared zero-argument gate cannot "count a broadside side once", so the ripple is cut whenever the cap is full (t8, *For every task*)
- **Plan:** §2.8 (`:369`) counts committed attacks per WEAPON part, "a broadside side counts once", with a cap of 2. *For every task* (`:47`) pins
  `attack_gate() -> bool (zero-argument telegraph_gate)`. The ripple (`:363-365`) lets the mid and stern mounts reach TELEGRAPH only 0.25 s and 0.5 s after the bow.
- **Code:** `ModularHull.build_mounts()` gives the same unbound Callable to every mount (`turret_mount_builder.gd:29`), and `TurretMount._track_step()` calls it with no
  arguments (`turret_mount.gd:282`). The gate therefore cannot tell which part is asking.
- **Failure case:** the port bow mount is in TELEGRAPH and the rack is committed, so 2 of 2 parts are committed. When the port mid mount asks, the gate sees the cap reached and
  refuses it, even though its own side is already counted. The volley is cut to its bow mount every time another weapon is busy. Row 2 (`:380`) would still pass in isolation,
  and the measured density row would measure a weaker boss than the one designed.
- **Fix:** after `build_mounts()`, rebind each mount's `telegraph_gate` to a per-part gate, for example `attack_gate_for.bind(part_id)`. The mount still calls a zero-argument
  Callable, so the Ph11 decision stands. The per-part gate allows a part that is already committed and otherwise applies the cap.
- **Row to add:** with the rack committed and a cap of 2, a port volley still leaves all three mounts. Update the Brain API line in *For every task*.

### B3. The torpedo's "3 HP, the 3rd hit defuses it" is in the wrong units (t4)
- **Plan:** §2.4 (`:180`) gives the torpedo `Health.max_health 3`, and the row (`:193`) says "2 player hits do not defuse, the 3rd does".
- **Code:** `EnemyOrdnance._on_hurt(damage)` subtracts the damage amount, not a hit count (`enemy_ordnance.gd:307-310`). The player's default shot deals 50 (`bullet.tscn:47`,
  `weapons/modes/default.tres:16`), Gatling 14, Spread 25 and Sniper 40.
- **Result:** a 3 HP torpedo dies to any single shot. The row can only pass with a hand-emitted 1-damage hit, which would pin behaviour that no player can produce.
- **Fix:** author the torpedo's `max_health` in damage units, from the shipped weapon modes. For example 101 to 150 means three Standard shots. State the intended number of hits
  per weapon, and write the defuse row with real player bullets, or with damage read from the mode `.tres` files.

### B4. The gate-room target is not grounded in a measurement, and the whole Dreadnought chain waits on it (t1, t6)
- **Plan:** §2.14 (`:474-477`) and t1's acceptance criteria (`tasks.json:7`) require freeing at least 12 s "by the `tests/README.md` rules 1–3 only". The plan names no
  candidate file and gives no wall-versus-CPU measurement.
- **Evidence from earlier phases:**
  - Ph10 t1 already took the tick-paced files to 16× (`tests/README.md` → *Phase 10 t1*). Its trial found about 18 more clock files "no faster".
  - Its note for the next recovery says the rest of the time is CPU-bound (`tests/README.md:672`): `test_fighter_squad.gd` takes 45 s, and the probe `before_all()`s need a
    cheaper `EnemyWorld.projectile_world_rect()`, which is a production change.
  - Ph8 t1 recorded "Rules 1-3 had nothing left to give" (`:601`) and freed its time with a bit-identical production speed-up instead.
- **Plausible candidates that remain:** the files still on 8× that were not in Ph10's trial: `test_fighter.gd`, `test_sniper.gd`, `test_space_fortress.gd`,
  `test_fortress_weapons.gd` and `test_fortress_incoming_damage_paths.gd`. None of them is measured.
- **Why it blocks:** t6 depends on t1, and t7 to t14 depend on t6. An all-or-nothing "≥ 12 s or escalate" criterion that rules 1 to 3 cannot meet stalls the whole phase.
- **The real need is smaller:** 225.2 + 13.8 = 239.0 s, so only about 2 s is strictly needed to stay under 237 s. About 6 s gives margin for ±1–3 s of noise.
- **Fix:**
  - Put a measured inventory in §2.14: the `scripts/gate-time.sh` slowest-file list plus `time godot … -gselect=` wall versus CPU for the still-8× files.
  - Set t1's acceptance to the headroom actually needed, with an escalation path.
  - Explicitly allow the Ph8 t1 route of a bit-identical production speed-up proven by a differential run, or say why it is excluded.
- **Smaller point:** t2 to t5 do not depend on t1, so "t1 first" in §3 is not enforced. That is harmless at 2.2 s, but say so.

## Minor

### M1. Movement row 2's expected ratio contradicts its own numbers, and `listing` can choose an orbit it cannot turn (t7)
- `:338` expects the starboard-turn radius divided by the port-turn radius to be "≈ 1 / 0.35 within 10 % (yaw bias included in the expected value)". With the §2.7 numbers
  (`:318-320`) and the port engine dead:
  - the port turn is 0.35 + 0.08 = 0.43 rad/s;
  - the starboard turn is 0.35 × 0.35 − 0.08 = 0.0425 rad/s;
  - so the ratio is about 10, not 2.86. The 18 px/s drift changes both radii as well.
- Also, a 700 px orbit at 0.65 × 120 px/s needs 0.111 rad/s. If the starboard broadside is the one still alive, the side rule (`:310`) picks a clockwise (starboard) orbit that a
  port-dead hull cannot hold.
- **Fix:** state the expected value as the formula over the config. Decide whether the side choice should prefer the side the hull can still turn to while it is listing.

### M2. Assault racetrack geometry is underspecified (t7)
- `:327-330` puts both waypoints on y 360 with U-turns "through the top" at a radius of 218 px. A 180° turn at that radius ends on the opposite heading at y ≈ −76.
- So it is a racetrack with an upper leg mostly above the view, which is consistent with "crossing left engages port" downward. It cannot be two crossings on y 360.
- **Fix:** say this explicitly, together with its consequence: about half of each lap is mostly off-screen, and the view-rect fire gate silences much of that leg. Or pick a
  different pattern.

### M3. Volley expectations ignore the Heavy Cannon's two-shell burst (t8)
- `heavy_cannon_mount.tscn` authors `burst_count = 2` and `burst_gap = 0.35` (`:10-11`). A three-mount side therefore fires six shells, interleaved at 0, 0.25, 0.35, 0.5,
  0.6 and 0.85 s.
- Row 2 (`:380`) speaks of "a volley's three shells", and the density reasoning should count six.
- **Fix:** either say "the first shell of each mount" or author a one-shell broadside scene (this ties into B1's authoring path).

### M4. The `quiet` fixture would not silence the mounts (t6, t7)
- `:222` writes 1e6 cooldowns on the private config. The mount cooldowns live in the mount scenes, though, not in `DreadnoughtConfig`.
- The fortress precedent (`test_space_fortress.gd:780-799`) silences through config fields the brain actually reads, and uses escort caps of 0.
- **Fix:** silence through `max_concurrent_attacks` / `critical_max_concurrent_attacks` 0, plus escort caps 0.
- Also name the position-overwrite `_tick` pattern there (`before + velocity * delta`, because a hand-ticked `move_and_slide()` moves by the idle delta). "Measured on
  positions" depends on it.

### M5. t12's dependencies are incomplete (t12)
- t12 depends only on t6 (`tasks.json:198-200`), but it draws the torpedo-tube head for t4's `TorpedoTubeMount` scene.
- Ownership of each engine's `Plume` is split between t9 (§2.6.2 `:241`, "`Plume` + `WakePoint` (t9)") and t12 (§2.12 `:453`).
- t12 also edits `dreadnought.tscn` / `dreadnought.gd`, which t7 to t11 change serially.
- **Fix:** add t4, plus t9 or t11, to t12's `dependsOn`, and name one owner for `Plume`.

### M6. No incoming-damage-path rows for the Dreadnought (t6)
- §2.6.6 / §2.6.7 prove only the bullet path through the hull (`:289`).
- CLAUDE.md names `test_fortress_incoming_damage_paths.gd` as the gate that closes the boss's collision-layer gap. It covers player homing and warhead rockets (HurtBox mask
  bit 32), real asteroids (bit 1024), and the mining laser through a layer-0 root with `is_laser_blocking()` false.
- These are authored scene values that fail silently.
- **Fix:** parameterise that file over the Dreadnought, or add the same rows to `test_dreadnought.gd`. Add a row that the Dreadnought's own rockets, torpedoes and shells never
  damage its parts while it moves (it is a moving launcher that can ram into its own fire).

### M7. `planSections` gaps (t9, t11)
- t9 places each `WakePoint` "40 px behind its nozzle", and t11 places each `Mouth` "just outside the hull edge on that part's side". Neither task lists §2.6.2, which holds the
  part positions and the hull rectangle.
- Both tasks can read the scene t6 built, but listing §2.6.2 costs nothing.

### M8. Torpedo registration is vague (t4)
- "Register it in `EnemyOrdnanceScenes` if that map is what lifetime / export rows read" (`:183`).
- `EnemyOrdnanceScenes.scene_for(kind)` is keyed by `Kind`, and `PURSUIT_BOMB` already maps to `pursuit_bomb.tscn`. A second scene of the same kind cannot be keyed that way.
- **Fix:** say a named const plus a lifetime row that reads the torpedo scene directly.

### M9. The detach chunk is a damaging hazard (t12)
- `DebrisFragment` registers a `HazardInfo` and carries `contact_damage` (`ram_fragment.tscn`: 12). Hazards and wrecks for bosses are Ph19's scope.
- **Fix:** author `contact_damage` 0 and keep the chunk visual (still self-freeing, deferred `spawn_into`), or state why boss-chunk damage belongs here.

### M10. t8 is large and close to two tasks (t8)
- t8 covers four weapon kinds, the ripple, the gate, the extreme phase and fairness, plus a 25-run density measurement with a three-lever tuning loop.
- Ph11 split the equivalent work into t7 (batteries and gate) and t16 (geometry weapons and density).
- Its own large-task plan may split it. Consider making the measured density a separate task, after t11, so it also sees the escorts and the final mount set.

## Checked and fine

- **Two phase tracks.** `BossPhaseDriver` is unchanged. Both tracks are valid ladders under `validate()`, and `test_boss_phase_rules.gd::_drivers_of()` collects both. The
  §25 declared changes hold on every path, including critical-on-crippled with thruster rate, cooldown 0.45 and core blink.
- **`ON_OWN_DESTROYED` against `boss_reinforcements.gd`.**
  - `_on_module_destroyed` → `_kill` can branch cleanly.
  - `_open` / `_launch` / `_hold` support "one chance".
  - The light is OFF after `EnemyModule.destroy()`, so restoring it to OFF is correct.
  - Escorts join the owner group, so the wake's exemption reaches them.
- **Wake.**
  - `HazardField._stress_enabled()` is overridable.
  - The `pulse_damage` default argument is bit-identical.
  - `spawn_into()` is deferred and self-freeing.
  - `HazardInfo.exempt_group` already drives avoidance.
- **Ram.** It reuses the Ram Corvette's `exposed_collision_damage` switch, and the contact-damage gate reads the spawn value. A boost keeps the corridor filter.
- **Corridor.** The racetrack's x range (42 to 1238) and its apex fit the corridor rect x −100 to 1380, y −380 to 1100.
- **Hub.** Draw 22 is appended. The 2500 px footprint at (−2970, 2970) clears the spawn, `fortuna_station` (about 3484 px away) and the TacticalSpace elements, which are
  all far east.
- **Rosters.** The `dreadnought/dreadnought.tscn` naming is picked up by the roster-completeness sweeps.
- **Geometry and values.**
  - The part hurtboxes lie inside the 208 × 448 hull and do not overlap.
  - `rocket_clear_radius` ≈ 255 px is correct.
  - `TORPEDO_TUBE` = 9 is the next enum value.
  - `Steering.turn_toward` / `clamped_lead_time`, `EnemyMover.boost` / `face_toward`, `TargetInfo` and `AnchorIdle` exist as named.
  - The Ram Corvette (0.65 s / 620 / 220 / 50) and Carrier `one_engine_*` figures quoted are correct.
- **Research.** It has tradeoffs per option and flags its weak sources (the Squadrons and Monster Hunter claims are from search summaries only).

---

VERDICT: CHANGES_REQUESTED

# Plan review, round 2

Revision 2 (`8dba0be`): I read all of `3-plan.md`, `tasks.json` (t1 to t15), the round-1 text above and the Phase 12 section of `DECISIONS.md`, then checked each claim against
the code on `agent/auto-dev` @ `8dba0be`. I did not run the gate.

All four round-1 blockers are fixed in the code paths they depend on, and the minors are handled. One new problem blocks approval: t3 cannot pass an existing intent gate as written.
The other new findings are minor. Several of them are rows whose expected numbers do not match the plan's own values; fix them in the same edit.

## Round-1 findings

| # | Status | Checked against |
|---|---|---|
| B1 fan authoring path | **RESOLVED** | `TurretMount.Variant` (`turret_mount.gd:31`) has 9 values, 0 to 8, so `MISSILE_FAN` = 9 and `TORPEDO_TUBE` = 10 are the next appends. `TurretMountBuilder.build()` (`turret_mount_builder.gd:16-38`) instantiates the variant's scene and calls `pool_specs()` before `setup()`. A standalone `missile_fan_mount.tscn` that authors `fan_count` 5 / `salvo_count` 1 therefore sizes its pools before the build reads them. `RocketBatteryMount.pool_specs()` (`rocket_battery_mount.gd:40-51`) feeds `EnemyRocketScenes.pool_size_for()`, which multiplies `salvo_count` (`enemy_rocket_scenes.gd:36-38`), so the planned `salvo_count × fan_count` is the right hook. `rocket_battery_mount.tscn` stays untouched. **But see N1 (head sprite).** |
| B2 per-part gate | **RESOLVED** | `TurretMount._track_step()` calls `telegraph_gate.call()` with no arguments and refuses on `!= true` (`turret_mount.gd:280-283`). A `brain.attack_gate_for.bind(part_id)` Callable takes zero arguments, so it works. Rebinding after `ModularHull.build_mounts()` is legal because `mounts_of(id)` exists (`modular_hull.gd:98`) and the gate is a plain var. The fortress keeps its shared gate (`space_fortress.gd:135`). Rule order is spacing first, then "already committed", then the cap, which ripples correctly: the bow's 0.7 s charge + 0.35 s burst keeps the side committed past the stern's entry at 0.5 s. Wording nit in N7. |
| B3 torpedo health units | **RESOLVED** | `EnemyOrdnance._on_hurt` subtracts the damage amount (`enemy_ordnance.gd:307-310`). `Health` has i-frames off by default (`health_component.gd:17`). `reset()` restores health (`:136`). Mode damages: `default.tres:16` 50, `sniper_shot.tres` 40, `spread.tres` 25 per pellet, `gatling.tres` 14. So 120 HP gives ceil 3 / 3 / 5 / 9, which matches §2.4 and §2.16. The defuse rows use real `bullet.tscn` shots plus damages read from the mode `.tres` files, with a one-hit-short boundary. `test_enemy_ordnance.gd` already runs at 16× (`:31`). The lifetime row's formula is wrong: N2. |
| B4 gate room | **RESOLVED** | §2.15 now has a measured wall/CPU inventory. The target is ≥ 6 s, against a need of 3.7 s: 225.2 + 15.5 = 240.7 and 240.7 − 237 = 3.7, and the allotments do sum to 15.5. Rule 4 is spelled out with a differential proof, matching the Ph8 t1 precedent at `tests/README.md:601`. There is an explicit ESCALATE path, and only t8 depends on t1. t2 to t7 add 7.7 s, giving 232.9 s, so the chain cannot stall before t8, and after t8 only by an owner decision. The 225.2 s baseline matches the Ph11 t11 row (`tests/README.md:704`). Allotment underestimates: N8. |
| M1 one-engine ratio / unholdable orbit | **RESOLVED** | ω_dead = 0.35 + 0.05 = 0.40 and ω_live = 0.175 − 0.05 = 0.125, so the ratio is 3.2. The speed term √(78² + 18²) = 80.0 gives radii of 200 / 640 px. The dead-side orbit is forced and the config invariants hold: 0.40 ≥ 78 / 700 = 0.111, and ω_live > 0. (The same fixed-number pattern comes back in t10 row 5: N4.) |
| M2 Assault racetrack | **RESOLVED** | The stadium's numbers check out. Leg extents are y 56–264 and 296–504, x 36–1244. r = 120 needs 90 / 120 = 0.75 ≤ 0.9. Pure pursuit with a 120 px lookahead on r 120 asks for the same curvature (chord 115 px, α 0.5 rad). The CCW side alternation is correct under the stated axes: lower leg heading right has starboard down, upper leg heading left has port down. |
| M3 six-shell volley | **RESOLVED** | Row 2 counts `3 × burst_count` and times the first shell of each mount. |
| M4 `quiet` fixture | **RESOLVED** | It silences through attack caps 0, escort caps 0 and `ram_first_delay`. With cap 0, gate rule 4 refuses and rule 3 never applies, because nothing is committed. `BossReinforcements._open()` with no room skips (`boss_reinforcements.gd:254-260`). The `hand_tick` overwrite pattern is named. |
| M5 t12 (now t13) deps / plume owner | **RESOLVED** | t13 depends on t4 and t12. `Plume` belongs to t13 only, and t9 adds only `WakePoint`s. |
| M6 incoming-damage / own-fire rows | **RESOLVED** (one row underspecified, N5) | There is a new `test_dreadnought_incoming_damage_paths.gd` mirroring `test_fortress_incoming_damage_paths.gd` (rows at `:148-316`). The own-fire rows are a static one (t8 row 9) and a moving one (t10 row 8). |
| M7 planSections geometry | **RESOLVED** | t9 and t11 list 2.6.2, and §2.9 / §2.11 repeat the coordinates. (A new gap for t12 is N9.) |
| M8 torpedo registration | **RESOLVED** | A named const outside `scene_for()` (`enemy_ordnance_scenes.gd:14-21` keys by `Kind`), and a direct lifetime row. |
| M9 damaging chunk | **RESOLVED** | The chunk is a visual-only `top_level` child: no areas, no hazard, self-freeing. |
| M10 t8 size | **RESOLVED** | The density measurement is split out as t12, after the interceptors. |

## New findings

### Blocking

**N1. t3: `MISSILE_FAN` cannot reuse the rocket battery's head, because `test_ph8_sprites.gd` forbids a shared head (t3; also the §2.13 text)**
- **Plan:** §2.3 (`3-plan.md:188`) and t3 say to add `MISSILE_FAN` to `test_ph8_sprites.gd` `HEADS` with `turret_head_rocket_battery.png`. §2.13 (`:576`) repeats "the MISSILE_FAN head is the rocket battery's".
- **Code:** three existing intent tests in `tests/integration/test_ph8_sprites.gd` rule that out.
  - `test_no_two_heads_share_a_texture` (`:187-192`) asserts that each `HEADS` texture is used once.
  - The same test asserts `HEADS.size() == TurretMount.Variant.size()`, so leaving the new variant out fails as well.
  - `test_no_two_heads_share_a_silhouette` (`:159-183`) requires a mask difference of at least `MIN_MASK_DIFF` between every pair, and an identical file gives a difference of 0.
- **Result:** t3 is unsatisfiable as written. "Every existing suite stays green unchanged" (*For every task*, `:60`) cannot hold. An unattended Direct-track agent has two ways out: weaken an intent gate, or ESCALATE and stall the t4 → t8 chain.
- **Precedent:** every variant has its own head, and Ph11 t3 drew two (`tests/README.md`, Ph11 t3 row).
- **Fix:**
  - t3 draws `turret_head_missile_fan.png` through `pixel-art-generation`. It must be strictly top-down, have a distinct silhouette (for example a multi-tube rack), be opaque at the pivot, and have its tip within 6 px of the `Muzzle` (`:147-155`).
  - Raise t3 to `medium` and say that it does art.
  - Correct §2.13 and §2.16.

### Minor

**N2. t4: the planned torpedo lifetime row fails with the plan's own numbers.**
- **Plan:** §2.4 (`:220-221`) checks "`max_distance` / slowest speed (160) fits `max_time`". That is 2400 / 160 = 15 s, which is more than 10 s.
- **Code:** `test_enemy_bullet_lifetime.gd` already has `_two_speed_kind_clears(window, launch, final, max_distance, max_time)` (`:300-303`), and the pursuit bomb uses it (`:316-321`). With the torpedo's numbers: 3 + (2400 − 480) / 320 = 9.0 s. The 200 px/s² ramp adds about 0.2 s, so 9.2 s, which is at most 10.
- **Fix:** name that helper, reading the torpedo scene's `steer_window` / `final_speed` and the tube's `launch_speed`.

**N3. t8: the broadside fairness inequality fails as shipped for the Assault player.**
- **Plan:** `broadside_fire_turn_cap × fire_range` = 0.35 × 900 = 315 px/s.
- **Code:** the fighter's `cruise_speed()` is `MoveState.move_speed` 360 (`move_state.gd:20`, `player_fighter.gd:128`). That is the reading the fortress fairness rows use (`test_fortress_weapons.gd:1035`), and 0.8 × 360 = 288 < 315. Only the Open Space ship (420, giving 336) passes.
- The lever is pre-approved, so this is not a stall, but the plan presents 315 as passing.
- **Fix:** ship the cap at 0.30, giving 270 ≤ 288. The orbit turn rates of 0.171 to 0.197 rad/s and the listing orbit of 0.111 rad/s stay under it. Say "max speed = `cruise_speed()`".

**N4. t10 row 5's fixed "≥ 2.5×" fails in the Assault harness.**
- The row runs in both harnesses, and in Assault the current rates are `assault_turn_rate`-based (§2.7.3 `:397-398`).
- ω_dead / ω_live = (0.9 + 0.05) / (0.45 − 0.05) = 2.375, which is less than 2.5.
- **Fix:** the M1 treatment. Assert the config formula for each mode, or the bare inequality `ω_dead / ω_live > 1` with the per-mode value printed.

**N5. Own ordnance against own ordnance and against its own moving hull is unexamined, and t10 row 8 is either vacuous or unsatisfiable depending on its setup (t8, t10).**
- **Code:** `EnemyRocket`'s `HitBox` is layer 32 with mask 128 | 512, and it opens once the rocket is `rocket_clear_radius + body_radius + arm_clearance` from the launcher's current position (`enemy_rocket.gd:17-20`, `:372-381`). The arming is latched. A Dreadnought part's `HurtBox` is layer 512 with mask 1120, so it sees layer 32. A torpedo `HurtBox` (`pursuit_bomb.tscn:32-33`: 512 / 96) also sees layer 32.
- **Consequence (a), rocket against own torpedo:** the centre rocket of a fan fired near the bearing of the slow torpedo meets it about 300 px out. The rack at (0, +110) is 86 px behind the tube at (0, +196). The torpedo moves at 160 px/s from a hull moving at 120 to 138 px/s, so it crawls off the bow at 22 to 40 px/s for 3 s. When the rocket meets it, the rocket detonates and chips 16 (`dumb_rocket.tscn:31`). Rack and tube committed together is legal: it is exactly row 3's boundary.
- **Consequence (b), t10 row 8:** a rocket "placed on the lane" head-on and already armed will hit a part, because there is no launcher guard. A rocket fired forward cannot be caught: 560 px/s against at least 520 px/s plus the inherited speed. So the row passes only when it proves nothing. The torpedo half is real and passes: the part masks do not see 512, and the proximity mask 128 does not see the parts.
- **Fix:**
  - Specify the row 8 scenario as the realistic one: fan and torpedo fired at the player, then a ram toward the player within their lives.
  - Add a measured row for rack-then-tube and tube-then-rack.
  - Pre-approve a fallback in order:
    1. Gate rule: rack and tube are never committed together.
    2. An opt-in, bit-identical owner-group skip on `EnemyRocket`'s impact. This is the Heavy Gunship's "measured, no launcher guard" precedent made explicit.

**N6. The torpedo tube almost never has the player in its arc, and t8 row 1 cannot fail for it.**
- The traverse is 30° about the bow (§2.8 `:434`).
- On approach the brain steers to the tangent point, so the player is at least asin(700 / d) off the nose: about 33° to 40° at 1100 to 1300 px.
- In the orbit the player is abeam.
- So the tube fires only when the player crosses ahead of the bow. In Assault the bow points down only at the left-end U-turn.
- Row 1 asserts "no torpedo from it over 20 s" after the tube's death with no control that it fired while alive, so the row holds whether or not the tube ever fires.
- §2.12's "a torpedo per 8 s" sanity figure is unreachable for the same reason.
- **Fix:**
  - Give row 1 an alive control: the same setup with the part live launches at least once from that part. The player is placed in its arc.
  - Call the tube a bow-chaser in `ENEMY.md`. Optionally widen the traverse.
  - Correct the sanity figure.

**N7. t8 row 3 says "the missile rack committed (in FIRE)".**
- With `salvo_count` 1, the rack spends no tick in FIRE. On the TELEGRAPH-end tick, `_fire_tick(0)` launches the salvo (`BurstClock` pre-loads `gap`), reports done, and `_end_fire()` runs on the same tick (`turret_mount.gd:118-123`). The torpedo tube behaves the same way.
- For these two mounts "committed" means TELEGRAPH (0.5 s and 1.0 s).
- **Fix:** say TELEGRAPH, and time the rack's charge to overlap the port volley's 0.5 s ripple.

**N8. Two allotments are below the plan's own measurements (t6, t12).**
- **t6:** the inventory (`:614`) puts `test_fortress_incoming_damage_paths.gd` at 1.5 to 2.0 s GUT, but its mirror is allotted about 1.0 s.
- **t12:** it runs 6 states × 5 positions × 660 = 19,800 ticks. At the quoted Ph11 rate (1.4 s per 13,200 ticks) that is about 2.1 s, against an allotment of 1.5 s. The Dreadnought also ticks more mounts than the fortress.
- Both stay under 1.5×, so nothing stalls. But the phase total rises to about 16.6 s, which ends at about 235.8 s with only a 6 s t1.
- **Fix:** raise the two allotments, and keep t1's 9 s target as the expectation.

**N9. t12's `planSections` lacks the Assault geometry and the fixture.**
- "Under each leg end" and the stadium are defined only in §2.7.3.
- `ladder()` / `kill_part()`, which put the boss into each phase state, are only in §2.6.1.
- **Fix:** add `2.7` and `2.6.1` to t12's list.

**N10. The Assault ram's extent is not bounded (t10).**
- From the lower leg (y 400) toward a player at y 600–650 the charge travels about 550 px, and the nose is 224 px ahead of the centre. The corridor filter (`assault_corridor_constraint.gd`, soft 120 / hard 450 per axis) damps the centre only past the visible edge.
- Row 6 says "the hull stays inside the world rect" without naming the rect, and gives no lever.
- **Fix:** name the rect (the corridor's hard band, or `EnemyWorld.projectile_world_rect()`). Pre-approve `assault_ram_overshoot` (for example 150) as the lever.

**N11. The hub's hunting footprint overlaps two patrols (t14).**
- The anchor at (−2970, 2970) is about 2055 px from both the Heavy Gunship anchor (2600 ring at 157.5°, about (−2402, 995)) and the Laser Tender anchor (112.5°, about (−995, 2402)). That is inside its own 2500 px footprint (leash 1400 + perceive 1100).
- `test_sector_hub_patrol.gd` sweeps triggers, pickups and the spawn, not other patrols. So a hunt that starts near its zone can follow the player into either fight.
- That may be acceptable (encounters are Ph13/14's), but it is unexamined.
- **Fix:** state it as intended in `ENEMY.md` / `DECISIONS.md`, or use the pre-approved bearing lever (135° ± 22.5°) to move it away. Either is fine.

## Checked and fine this round

- **Arithmetic.**
  - Allotments sum to 15.5.
  - t2 to t7 add 7.7 s.
  - `rocket_clear_radius` is √(104² + 224²) + 8 = 255.
  - Tube pool: ceil(10 / (8 × 0.45)) + 1 = 4.
  - Density sanity for `hunting`: 6 / 4.25 + 5 / 6.5 + 1 / 8 = 2.3 /s, and the peak in a 2 s window is at most 18 < 30.
  - Ram fairness: 1.2 × 0.6 = 0.72 ≥ (104 + about 20) / 360 + 0.25 = 0.59.
  - Stadium and one-engine radii: see M1 / M2 above.
- **§25.** Every path declares at least two aspects. `listing` declares 3, `crippled` 4, `critical` 3. The crippled-then-critical path changes thruster rate, cooldown 0.6 → 0.45 and the core blink. `test_boss_phase_rules.gd::_drivers_of()` collects both drivers.
- **`ON_OWN_DESTROYED`.** It fits `boss_reinforcements.gd` as it stands:
  - `_on_module_destroyed` → `_kill` is the branch point.
  - `_hold` closing a mid-OPENING door must not count as the breach's final close, and row 5 pins that.
  - `_open` records `light_before` = OFF after `destroy()`.
- **Dependencies.** No cycles. t3 → t4 serialises the enum. t8 → t9 → t10 → t11 → t12 → t13 serialises `dreadnought.gd` / the brain / the scene. t12 and t14 both edit `dreadnought_config.tres` only through levers on different fields.
- **`planSections`.** Every number used exists as a heading in `3-plan.md` (2.1 to 2.17, 2.6.1 to 2.6.8, 2.7.1 to 2.7.4, 1.1, 6, 7, 8).
- **Scope.** Every IDEAS §9 / §10 / §21–26 / §40 / §41 item listed in the review brief has a task and a row. Level placement, HUD, beams on parts, wrecks and tiers are out of scope with owners and reasons.
