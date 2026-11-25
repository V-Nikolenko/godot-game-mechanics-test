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
