# t5 — Heavy Gunship: hull phases, overheat-and-vent, weak points, emergency and rear missiles, the cannon shield

Task plan for Phase 10 t5. The design is the epic's approved plan (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.5, §2.9, §2.16) with the epic
review's findings N1 (cannon-shield flank row), 3 (rockets in Assault), 11 (VENT keeps a started burst) and 15 (own rockets). This file fixes the
build-level choices §2.5 leaves open and the test list. It does not redesign anything; each departure from a plan line is marked **(D)** and goes to
`DECISIONS.md`.

## Problem

After t4 the Heavy Gunship fights the same way from full health to its last hit point: its VENT / EMERGENCY phases are stubs and its rear missiles never
open. After t5 the fight has three stages read off the hull bar. Above 60 % it is defensive (t4). Between 60 % and 30 % it overheats: every four bursts
it must vent for 2.2 s, slowed, its two flank vents glowing orange, and a shot into an open vent hurts the hull twice. Below 30 % it is in emergency: it
boosts away every 5 s and, after each boost, opens its rear missile pod for 2 s at a pursuer behind it, while the batteries keep firing. It never leaves
the fight because it is hurt. The nose cannon carries a small frontal shield that only protects the cannon. A destroyed battery, cannon or missile pod
never fires again. In Assault the missile pod is shut the moment the ship's budget runs out, so its rockets cannot hold a section open.

## Design

### Hull phases (§2.5)
- `HeavyGunshipBrain.HullPhase { CONTROLLED, OVERHEAT, EMERGENCY }` (append-only), `var hull_phase`, `signal hull_phase_changed(hull_phase: int)`.
- `_update_hull_phase()` runs once per tick, after the DISENGAGE fast path and `_start()`, before the budget and the dispatch. It reads the actor's root
  `Health`: CONTROLLED while `current >= overheat_ratio · max`, OVERHEAT while `current >= emergency_ratio · max`, else EMERGENCY (both compares with a
  1e-6 slack, so 420 / 700 is CONTROLLED and 210 / 700 is OVERHEAT). **One-way:** `hull_phase = max(hull_phase, band)`; on a rise it emits once, with the new
  band (a jump straight to EMERGENCY emits once). A `repair()` never steps back. It is never evaluated inside a physics callback (a hit only changes `Health`;
  the brain reacts on its next tick), so every `set_vulnerable()` it causes is a direct call.
- While `hull_phase == EMERGENCY`, any fight phase (APPROACH, BROADSIDE, BREAK_AWAY, VENT) is replaced by `Phase.EMERGENCY` before the dispatch (also the
  APPROACH the hub idle hands over on COMBAT). The hub idle (IDLE / NOTICING / RETURNING) and DISENGAGE are unchanged in every band.

### Heat and VENT (§2.5 OVERHEAT)
- `var heat: int`. `bind_mounts()` connects each **gun** mount's (batteries, cannon) `phase_changed`. A burst **ends** when a gun mount enters COOLDOWN (the
  only way in is `_end_fire()`, so a burst cut by lost sight or arc counts too). It adds 1 heat only while `hull_phase == OVERHEAT` and the phase is
  APPROACH / BROADSIDE / BREAK_AWAY (never in VENT, never in CONTROLLED or EMERGENCY).
- After the dispatch, `heat >= heat_limit` (4) in those phases enters **VENT** on the same tick as the burst that filled it.
- `enter_phase(VENT)`: `heat = 0`, both vents `set_vulnerable(true)`, `mover.max_speed = config.max_speed · vent_speed_factor` (84), `vents_opened += 1`.
  `enter_phase()` gains an **exit hook**: leaving VENT for any phase closes the vents (`set_vulnerable(false)`) and restores `mover.max_speed =
  config.max_speed`, before the new phase's entry code (so DISENGAGE still writes its exit speed after it).
- `_tick_vent()`: first the clock (`_phase_time >= vent_seconds - CLOCK_EPS` → BROADSIDE, so the vents are open for exactly 132 ticks), then the arc and the
  broadside facing as in BROADSIDE (no break-away), then the weapons with the VENT rule.
- **VENT fire rule (D, review finding 11):** each gun mount gets `can_fire = <its normal permission> and mount.phase() == TurretMount.Phase.FIRE`. §2.5 /
  DECISIONS write `can_fire = mount.is_committed()`, but `TurretMount.is_committed()` is false for every projectile mount (it is the lance's COMMIT light,
  and overriding it on `BurstCannonMount` would light COMMIT on every Phase 8 turret's burst), so the literal rule would cut the burst it is meant to keep.
  The intent is unchanged: a burst already firing finishes (`BurstCannonMount` keeps its `BurstClock` while `can_fire` holds), a TELEGRAPH in progress is
  cancelled back to TRACK, and none starts. The missiles mount is closed in VENT (VENT only exists in OVERHEAT).
- **EMP / rail:** an EMP freezes the brain, so a VENT in progress stays open for the EMP window (the vents keep glowing: their light shows what is true);
  `on_suspended()` closes a VENT through the exit hook.

### EMERGENCY (§2.5)
- `enter_phase(EMERGENCY)` primes `_emergency_clock = emergency_period`, so the first boost happens on its first tick (the "lurch" when the hull goes
  critical), then one every `emergency_period` (5.0 s). `_tick_emergency()`: the clock counts; when it is `>= emergency_period - CLOCK_EPS`, the mover is not
  boosting and (Assault) `budget.remaining() >= emergency_boost_seconds` and no DISENGAGE is pending, it calls `mover.boost(Steering.break_contact(pos,
  player, player_vel, -orbit_dir, 1.0), emergency_boost_speed 420, emergency_boost_seconds 0.9)`, resets the clock, counts `emergency_boosts` and keeps the
  commanded unit direction in `emergency_boost_dir` (public, read by row 12; review round 2, R2-3). A refused
  boost retries every tick and opens no window. Between boosts: `_arc_motion()` at `held_range()` and the broadside facing; during a boost the arc re-syncs
  (`_orbit_synced = false`) and the facing stays broadside, so **the batteries keep firing**. No min-range break-away and no heat or VENT in EMERGENCY.
- `held_range()`: EMERGENCY → `emergency_range` 800 (Open Space) / `assault_preferred_range + emergency_assault_extra` 120 = 540 (Assault).
- **Missile window:** open while `emergency_boost_seconds <= _emergency_clock < emergency_boost_seconds + missile_window` after a boost (0.9 – 2.9 s after it
  started). **Missiles `can_fire`** = phase EMERGENCY ∧ window open ∧ the player inside the rear `missile_rear_arc_deg` 200° (angle between the nose and the
  bearing to the player ≥ 80°) ∧ the hull in the Assault view (the t4 turret rule) ∧ (Assault) the budget still running (`not _expiry_seen and not
  _disengage_pending`). No line-of-sight check: the rocket battery fires past cover.
- **Missiles' own telegraph gate (D: §2.5 does not say how a salvo meets the window's end):** `bind_mounts()` replaces the Missiles mount's
  `telegraph_gate` (t4 gave every mount `attack_gate`) with `missile_gate_open()`: true only in EMERGENCY when the window has at least `salvo_window +
  ATTACK_GATE_MARGIN` left (`salvo_window` = `charge_seconds + (salvo_count - 1) · salvo_gap`, read duck-typed from the mount: 0.85 s) and, in Assault, the
  budget too. So a salvo is never cut by the window closing and every rocket of it leaves inside the window and inside the budget.
- **Assault closure (§2.5, review finding 3):** the Missiles mount fires only while the budget runs; `_enter_disengage()` `scan(0.0)`s it (any live salvo is
  cut, the tube glow cleared; the gate means none is live in practice) and nothing ticks it afterwards. So every rocket is launched before the budget ends and
  lives ≤ the longest `max_time` of the mount's pool scenes (PURSUIT 6.0 s, read from the scenes). t11 adds the rocket term to the deadline rows.
  DECISIONS records this as the **bounded exception** to "persistent ordnance stays out of `ENEMIES_CLEARED` sections".
- **It never despawns on health:** nothing in the brain frees it outside DISENGAGE (Assault only); in Open Space it fights until killed.
- **Reach in EMERGENCY (review round 1, finding 3; logged in DECISIONS):** the 800 px Open Space hold (± `range_drift` 90) is beyond the batteries'
  ≈ 770 px broadside reach (`fire_range` 700 from the muzzle) and a boost carries the hull past the rocket pod's 900 px, so the batteries and the pod
  reach **a pursuer**, not a player who stays back: that is the "aggressive retreat" of §2.5, and the rows use a pursuer. `emergency_range` stays the §2.16
  starting value.
- **Reach in Assault (review round 2, R2-2; logged in DECISIONS and ENEMY.md):** the turret rule ("never fire from outside the view") applies to every
  mount, and an emergency boost (≈ 380 px) carries a hull holding 540 px above the player out of the fixed 1280 × 720 view: the reviewer's probe (t4 brain,
  Assault harness, 18 runs) had the hull in view on only 0–46 of a window's 121 ticks, never the 51 contiguous ticks a salvo needs. So in Assault the pod
  rarely completes a salvo and the batteries pause while the hull is out of view after a boost. Accepted (fewer persistent rockets, which also eases t11's
  rocket term); the Assault rows hold the hull inside the view so they test the rules, not the geometry.
- **The pod fires after every other boost (review round 1, finding 8; logged in DECISIONS and ENEMY.md):** the rocket battery's own `cooldown_seconds`
  5.5 (`rocket_battery_mount.tscn`) outlasts `emergency_period` 5.0, so a salvo 0.9–1.75 s after one boost leaves the mount cooling past the next window's
  last legal TELEGRAPH (2.0 s after that boost). §2.5 says the pod is "allowed to fire" in each window; one salvo per two boosts is the shipped cadence and no
  row asks for one per window.

### Own rockets (§2.5, review finding 15; revised in review round 1, finding 2)
Accepted as the plan says and **measured** by the Open Space 60 s row below (row 15). **What a self-hit is:** the damage of a rocket hit is dealt by the
*target's* `HurtBox._on_area_entered` (any HitBox on its mask: the hull's 1121 and every part's 1120 see the rocket HitBox's layer 32), not by the rocket,
so an exemption inside `_on_hit_box_area_entered` (§2.5's wording) would only stop the blast and the 18 damage would still land (D). A self-hit is therefore
"an **open** rocket HitBox overlapping the launcher's hull rectangle" (every part lies inside it), and the only working fix is on the rocket's HitBox.

**If row 15 shows one — the launcher guard (D, replaces §2.5's exemption; tightened in review round 2, R2-1):** `_update_arming()`'s arming test and
its `_armed` latch stay exactly as today (so the first opening happens on today's tick for every rocket of every launcher, and
`test_enemy_rockets.gd::test_a_moving_launcher_never_overruns_its_rocket` keeps reading `is_armed() == (d >= arm_at)`). A separate `_update_guard()`,
called from `_tick()` after it, applies **only while `_had_launcher` and the launcher is live** (a submunition's launch point is not a launcher): an armed
rocket inside `_guard_radius()` of its launcher has its HitBox closed (`monitoring` / `monitorable` deferred, as `_mark_done()` does), and it reopens on
leaving; the HitBox is written **only on a change**. `_guard_radius()` = the arming radius (`rocket_clear_radius() + body_radius + arm_clearance`) + the
**closing** speed · delta, closing speed = `max(0, −(rel_pos · rel_vel) / |rel_pos|)` with `rel_pos` = rocket − launcher and `rel_vel` = `_heading · _speed −
launch_velocity()`: zero while the rocket recedes (so on the way out the guard is exactly the arming radius and never closes an opened HitBox), and a hull
boosting at a rocket closing on it cannot cross the 12 px margin (95.2 + 8 against the 91.2 px half-diagonal) in one step. The deferred write is made from
`_physics_process` and lands in that frame's message-queue flush, before the physics step (the order `enemy_rocket.gd`'s `_end_after_overlaps()` note
documents); a reopen that already overlaps something forms no pair (`test_seeking_ordnance.gd`'s measured fact), so it cannot double-hit.
`is_armed()` keeps meaning "armed once" (the WARHEAD trigger and every Ph5 row read it); a new `is_hit_open()` reports the logical state (armed, not done
and outside the guard). Every launcher gains it (the Missile Corvette, the turret rocket battery): the Ph5 / Ph8 intent "a rocket never hits its own
launcher" (`rocket_battery_mount.gd` header) becomes true after arming too, **except a triggered WARHEAD**, which returns before the arming code
(`enemy_rocket.gd` `_tick()`: stopped dead, counting to its blast) and keeps its HitBox as it was. Rows: real physics in `test_enemy_rockets.gd` — a rocket turned back through a still
launcher (a real Heavy Gunship) leaves its `Health` and every part unchanged and flies on; control: the same rocket through a second gunship that did not
launch it deals `impact_damage`. A DECISIONS line. If row 15 shows no self-hit, `enemy_rocket.gd` is untouched.

### Cannon shield (§2.5, §2.9)
- Scene: `Modules/Cannon/Shield` (`EnemyShield`, UID-less `ext_resource`), `radius` 26 (the cannon rect's half-diagonal 20 + 6, the support ship's
  "hull + 6" rule).
- Config (Defense group): `shield_arc_deg` 120, `shield_capacity` 60, `shield_regen_delay` 2.0, `shield_regen_seconds` 4.0, `shield_reboot_seconds` 5.0.
  `HeavyGunship._ready()` writes them onto the shield, `attach()`es it to `Modules/Cannon/HurtBox` and `face()`s it along the nose. Every node is looked up
  with `get_node_or_null` (the exit probe strips `Modules`).
- The brain `face()`s it along the nose every tick (every phase but DISENGAGE): `face()` snaps, so it lags the hull by at most one tick's turn (0.9 / 60 rad).
- When the cannon is destroyed (`ModularHull.module_destroyed`) the root frees the shield (`queue_free`; its `_exit_tree` releases the absorber slot), so a
  wreck draws no arc.
- **Rows (D, epic review N1; analysis corrected in review round 1, finding 4):** `EnemyShield` decides by the bearing from the cannon's centre (0, 60) to
  `hit_box.global_position` as Godot reports it in `area_entered`, one physics step after the move that made the overlap. Under the flush-edge rule a plain
  bullet reaches the cannon only through its 32 px nose edge (y 72), and by the time it is reported it can be up to 15 px past that edge (900 px/s), its
  capsule tip ≈ 5 px ahead of its origin: dy 2–17 px, dx up to ≈ 18 px, so a frontal shot near the edge's corners can read up to ≈ 83° off the nose and
  **slip past the 60° half-arc** (≈ a third of shots spread evenly over the edge; a player homing rocket arriving from a front quadrant likewise). That
  corner leak is accepted (the shield is a frontal plate on the cannon's centre line, not a seal) and recorded in DECISIONS and ENEMY.md; a centre-line
  shot is always absorbed (dx 0). §2.5's "a flank bullet into the cannon's edge damages the cannon" cannot happen with a plain bullet (a flank shot is
  spent on the bare flank first). The row becomes N1's replacement plus one shot that does reach the cannon from the side: the player's **Sniper Shot**
  (`unlimited_pierce`) crosses the hull and meets the cannon at exactly 90° off the nose (hull-local y 60), outside the arc whatever the penetration.

### Lights (§2.9)
- `StateLight.State` gains **`VENTING`** (appended; orange `Color(1.0, 0.55, 0.1)` at `MAX_ALPHA`). `test_state_light.gd` gets a row.
- Each of the six parts gets a `Light` child (`StateLight`, at the part's centre; t9 may move it). The brain caches `[part, light, mounts]` at
  `bind_mounts()` and, in `_update_light()`, sets (only on change): a vent → VENTING while the phase is VENT, else OFF; a weapon part → CHARGING while one of
  its mounts is in TELEGRAPH, else OFF; a wreck is skipped (`EnemyModule.destroy()` already turned its light OFF and nothing turns it back on).
- The hull `StateLight` keeps t4's mapping, now in VENT and EMERGENCY too, and in EMERGENCY it also reads the Missiles mount.
- `on_emp_started()`: hull light and weapon-part lights OFF (vents unchanged, above). `on_suspended()` and `_enter_disengage()`: every light OFF.
- **EMP in VENT (D, review round 1, finding 7; logged in DECISIONS):** the brain is not ticked for an EMP window, so a VENT in progress keeps its vents open
  and glowing for the window and resumes its 2.2 s clock after it: under the player's 5 s EMP Blast the weak point stays open up to ≈ 7.2 s. That is the
  EMP's reward (the hull cannot cool while it is stunned), not a stuck state: the clock resumes and closes the vents.

### Config (`heavy_gunship_config.gd` / `.tres`, flat)
`@export_group("Phases")`: `overheat_ratio` 0.6, `emergency_ratio` 0.3, `heat_limit` 4 (int), `vent_seconds` 2.2, `vent_speed_factor` 0.6,
`emergency_period` 5.0, `emergency_boost_speed` 420.0, `emergency_boost_seconds` 0.9, `missile_window` 2.0, `missile_rear_arc_deg` 200.0, `emergency_range`
800.0, `emergency_assault_extra` 120.0. `@export_group("Defense")`: the five shield fields. All §2.16 starting values; the header's "arrive with t5" goes.

### Unchanged on purpose
- CONTROLLED is bit-identical to t4 in motion and fire (the dispatch, rng draws, mover requests and mount ticks; the missiles mount still gets `can_fire`
  false, so its new gate is never asked). Level-1 replays and the exit probe (DISENGAGE fast path stays first; `Modules` stripped; every new node sits
  under `Modules` or is visual) stay green unchanged.
- **One t4 row changes (review round 1, finding 1; a t4-gate change logged in DECISIONS):** `test_a_bullet_through_each_exposed_edge_hits_that_part_and_the_hull`
  fires straight up the cannon's nose edge, which the t5 shield absorbs (`hit_absorbed`, no `damaged`). The row frees `Modules/Cannon/Shield` before its
  cannon shot (`_exit_tree` releases the absorber slot), so it still proves the cannon is reachable through its edge for the bullet's damage; the shielded
  frontal hit is row 10's.
- `EnemyModule`, `ModularHull`, `EnemyShield`, the mounts and `enemy_rocket.gd` (unless the self-hit row forces it) are not edited.

## Build sequence
1. **Tests first:** the rows below in `test_heavy_gunship.gd` and the `VENTING` row in `test_state_light.gd`; run them red.
2. Config fields + `.tres`; `StateLight.VENTING`.
3. Brain: `HullPhase`, `_update_hull_phase()`, the EMERGENCY replacement, heat, VENT (entry, exit hook, tick, fire rule), EMERGENCY (boosts, window,
   missiles' can_fire and gate, DISENGAGE closure), lights, shield facing, EMP / rail hooks.
4. Scene: `Shield`, six `Light`s. Root: shield setup and free-on-destroy.
5. Rows green in both harnesses; the self-hit verdict (the launcher guard and its rows only if row 15 measures a self-hit).
6. t4 rows, roster gates and level-1 gates green; `scripts/check-test-leaks.sh`; two `scripts/gate-time.sh` runs; `bash /agent/verify.sh`.
7. `ENEMY.md` (phases, shield, lights), the CLAUDE.md Heavy Gunship line, DECISIONS t5 notes, the gate-time row (via `updating-project-docs`).

## Test plan (`tests/integration/test_heavy_gunship.gd`, new section "Phases (t5)"; hand-ticked at 1/60 unless marked real physics)
Long scenarios are run once per harness and shared by several tests (gate-time rule 2: a static memo keyed by mode, holding plain data only).

**The heat run** (memo, both harnesses). The hull is held at a fixed point and rotation (position and rotation written back after each tick), the
player still at hull-local bearing 67.5° (between port and nose) 420 px out, so the port battery (arc ±80° about +x) and the cannon (55° – 125°) both bear.
Phase A at full health until 4 gun bursts have ended (cap 15 s); then `health.decrease(300)` (57 %); phase B until 3.5 s after the first VENT ends (cap
24 s; review round 1, finding 6). Logged per tick: brain phase, both vents' `is_vulnerable()`, `mover.max_speed`, every part light and every mount's phase; per event: burst ends,
TELEGRAPH / FIRE entries and `round_fired` (mount, time, round scene, speed).
1. `test_heat_builds_only_in_overheat_and_the_fourth_burst_vents` — A: ≥ 4 burst ends, `heat` 0, no VENT, CONTROLLED; B: VENT is entered on the tick of
   the 4th burst end after OVERHEAT began, `heat` back to 0 on entry, VENT lasts 2.2 s (± 1 tick).
2. `test_venting_starts_no_burst_and_fires_again_after` — from VENT entry until the end of every burst already in FIRE at that tick, then to VENT's end: no
   TELEGRAPH or FIRE entry and no round from any mount; a gun telegraphs again within 3.5 s of VENT's end (control).
3. `test_the_vents_open_glow_and_slow_the_hull_only_while_venting` — every tick: each vent `is_vulnerable()` == (phase is VENT), its light VENTING ==
   (phase is VENT), `mover.max_speed` 84 in VENT and 140 outside.
4. `test_a_gun_parts_light_is_yellow_exactly_while_its_mount_charges` — every logged tick, each weapon part's light is CHARGING iff one of its mounts
   is in TELEGRAPH; the hull light keeps t4's mapping.
5. `test_the_cannon_fires_heavy_shells_at_220_px_s` — every cannon round's scene is `EnemyRounds.HEAVY_SHELL` and its `speed` 220; ≥ 1 cannon round.

**Forced VENT mid-burst** (both harnesses, not memoised): same held geometry, CONTROLLED; tick until the port battery has fired its first round of a
burst, then `brain.enter_phase(Phase.VENT)`.
6. `test_a_burst_firing_when_vent_starts_finishes_all_its_rounds` — that burst fires all `burst_count` (4) rounds, its FIRE ends on the burst clock
   (`(burst_count - 1) · burst_gap` ± 1 tick), then no TELEGRAPH / FIRE / round from any mount until VENT ends; a TELEGRAPH in progress at the forced entry
   (the cannon, if so) goes back to TRACK with no round.

**Hull bands** (both harnesses):
7. `test_hull_bands_are_read_off_the_bar_and_never_step_back` — HP 427 → CONTROLLED, 420 → CONTROLLED (boundary), 419 → OVERHEAT, 413 → OVERHEAT,
   210 → OVERHEAT (boundary), 209 → EMERGENCY, 203 → EMERGENCY; `repair()` to 490 (70 %) → still EMERGENCY and the brain phase still EMERGENCY;
   `hull_phase_changed` emitted exactly `[OVERHEAT, EMERGENCY]`. A second gunship cut from 700 to 100 in one hit emits `[EMERGENCY]` once.

**Vents and direct emitters**:
8. `test_a_shot_into_a_vent_hurts_the_hull_twice_only_while_it_vents` (real physics, 16×, both harnesses, hull still) — a bullet through
   `VentPort`'s edge: closed → hull −50 once, vent `damaged` 0, `deflected` 1; after `enter_phase(VENT)` → hull −100, vent `damaged` 1; after
   `enter_phase(BROADSIDE)` → hull −50, vent `damaged` unchanged.
9. `test_the_beam_and_the_nova_never_reach_a_closed_vent` (both harnesses; `BeamBehavior.tick()` called by hand, the nova as in `test_enemy_module.gd`)
   — CONTROLLED: a mining beam along the vents' line (hull-local y −34, from the port side; no other part centre and not the hull centre within 12 px)
   for 2 s: both vents `deflected` > 0, `damaged` 0, the hull unchanged; one nova: the hull −50 exactly (its own hit, nothing forwarded), each vent pinged
   once, the batteries, cannon and missiles −50 each. Control: in VENT the same beam for 0.5 s makes the vents report damage and the hull drop.

**Cannon shield**:
10. `test_the_cannon_shield_eats_frontal_shots_and_never_covers_the_hull` (real physics, 16×, both harnesses, hull still), in order: a **Sniper Shot**
    (`unlimited_pierce` bullet) from the port side at the cannon's level (hull-local y 60): hull −50, cannon −50, shield points 60 (outside the arc); a
    frontal bullet into the cannon's nose edge: consumed, cannon unchanged, hull −50, shield 10; a second frontal bullet: consumed, cannon unchanged, hull −50,
    the shield `broken`; a third frontal bullet (rebooting): cannon −50, hull −50; a plain bullet from the port side at y 60: hull −50 and the cannon
    unchanged (a plain round cannot reach it through the flank).
11. `test_the_cannon_shield_takes_its_config_follows_the_nose_and_goes_with_the_cannon` (both harnesses) — the shield holds the config's five values and the
    cannon hurtbox's absorber slot; with the hull turned to 2.0 rad, one tick later `facing()` is within 1° of the nose; `Cannon.destroy()` frees it.

**The emergency run** (memo, both harnesses). HP set to 200 (EMERGENCY) at spawn; the player on the hull's starboard (local −x) 450 px out at spawn, so
the starboard battery is the chosen side. **0 – 20 s a pursuer** (review round 1, finding 3): the player is re-placed every tick 450 px from the hull on its
current bearing from it (it keeps pace with the retreat; inside both the batteries' ≈ 770 px and the pod's 900 px reach); at 20 s `BatteryStarboard` and
`Missiles` are destroyed; 20 – 50 s the player is re-placed every tick on the hull's starboard beam (hull-local −x, 450 px; "kept on the starboard side").
**In Assault the hull's position is held** (written back each tick at a point inside the view, the heat run's idiom; its rotation stays the mover's) so
the boosts cannot carry it out of the fixed view and the turret rule cannot decide the rows (review round 2, R2-2); with the hull held, the 0–20 s
pursuer's bearing is constant. Logged: boost starts (mover `is_boosting()` rising edges, with the hull and player positions and the brain's
`emergency_boost_dir`), the Missiles mount's TELEGRAPH / FIRE entries and rounds with the player's angle off the nose, the starboard battery's entries and
rounds, part lights; in Assault also that the hull was inside `EnemyWorld.view_rect()` on every tick (precondition).
12. `test_emergency_boosts_away_every_5_s` — boost starts at 0, 5, 10, … 45 s (± 1 tick: 10 boosts, through the losses: "Missiles lost → it still
    boosts"); in both harnesses each boost's commanded direction points away from the player (`emergency_boost_dir · (hull − player) > 0`); in Open
    Space only, each boost before 20 s also moves the hull away (displacement over the boost · away > 0; review round 2, R2-3: the corridor filter acts
    on boost velocity in Assault, and the Assault hull is held).
13. `test_the_rear_missiles_fire_only_in_their_window_at_a_player_behind` — ≥ 1 salvo before 20 s; every Missiles TELEGRAPH / FIRE entry and round lies in
    `[boost + 0.9, boost + 2.9)` of a boost and has the player ≥ 80° off the nose. **Front control** (its own 8 s run per harness): the player re-placed
    every tick on the nose (hull-local +y, 450 px), ≥ 2 boosts, and the Missiles mount never telegraphs.
14. `test_a_destroyed_battery_or_missile_pod_never_fires_again` — control: the starboard battery and the Missiles mount each fired before 20 s; after the
    destruction, for 30 s: no TELEGRAPH / FIRE entry and no round from either, both mounts UNPOWERED, both part lights OFF.

**Open Space chase** (Open Space only, not memoised):
15. `test_in_open_space_it_stays_in_the_fight_60_s_into_emergency_and_never_hits_itself` — HP 200; the player chases at 300 px/s (toward the hull, holding
    at 250 px). The gunship's rockets are hand-ticked too (each launched rocket's and its `ProjectileLifetime`'s `set_physics_process(false)`, then `_tick(DT)`
    / `_physics_process(DT)` every tick); after a tick in which a rocket expired the row awaits one `process_frame` so the pool's deferred recycle runs
    (2 + 2 pooled rockets would otherwise run dry). Over 60 s: never freed or queued for deletion, phase EMERGENCY at the end, never further than
    `lose_radius` from the player; ≥ 4 rockets launched; **no tick on which a rocket's HitBox is open and its shape overlaps the hull's root hurtbox
    shape** (`Shape2D.collide` with both global transforms; every part lies inside that rectangle). "Open" is `is_armed()` on today's rocket (an armed
    HitBox stays open for the rest of its life) and `is_hit_open()` if the launcher guard is added. The row also asserts the hull `Health` and every
    part's `damaged` count unchanged, but those see physics events only in the awaited frames (the rockets are hand-ticked between them), so the overlap
    check is the real measurement (review round 1, finding 2). Hand-ticked rather than real physics: the 8× clock would cost ≈ 7.5 s of gate time on its
    own (60 s of game time), three times the task's allotment; the collide test is the overlap the physics step would report, on the same 1/60 steps.
    The rocket count and the closest an open rocket came to the hull are printed.

**Assault closure** (Assault only; in every run of 16 / 16b the hull is held at a point inside the view with its starboard to the still player, position
written back each tick, and the row asserts `EnemyWorld.view_rect().has_point()` on every tick as a precondition: review round 2, R2-2):
16. `test_in_assault_the_rear_missiles_close_with_the_budget` — `engage_seconds` E, the player still; EMERGENCY forced R s before the budget ends.
    R = 3.5: ≥ 1 salvo, every rocket launched with ≥ `ATTACK_GATE_MARGIN` of budget left; R = 1.0: no salvo (the 0.9 s boost leaves 0.1 s); **R = 1.3
    (review round 1, finding 5): the window opens with 0.4 s left, inside (0, `salvo_window` + margin), and no Missiles TELEGRAPH starts (the gate's budget
    clause); control: the same run with the Missiles gate bypassed does telegraph**; in all gated runs, no rocket and no Missiles TELEGRAPH / FIRE after the
    budget expires, and the Missiles mount is in SCAN from DISENGAGE on.
16b. `test_a_deferred_expiry_cuts_a_rear_salvo_at_the_budget` (Assault; epic review N5, review round 1, finding 5) — R = 1.3 with the Missiles gate
    bypassed (so it telegraphs with 0.4 s left and its rockets would leave after the budget), and 0.3 s before expiry the row starts a 1.0 s
    `mover.boost` at 1 px/s (negligible; the hull is held anyway) so expiry is deferred (`_disengage_pending`) and the brain keeps ticking EMERGENCY past
    it. Preconditions: the Missiles TELEGRAPH started before expiry, **the Missiles mount is still in TELEGRAPH on the tick before expiry** (so nothing but
    the `can_fire` budget clause can stop its FIRE; review round 2, R2-2), the hull was in view throughout, and the phase on the expiry tick is still
    EMERGENCY. Assertion: no Missiles FIRE and no rocket at or after expiry (the `can_fire` clause alone; DISENGAGE's `scan(0.0)` has not run yet).

**Config and lights**:
17. `test_the_config_is_applied_and_carries_the_plan_values` (extended) — the 17 new fields' §2.16 values.
18. `tests/unit/test_state_light.gd::test_venting_is_orange` — `VENTING` is appended (value 4) and shows orange at `MAX_ALPHA`.
19. The t4 row `test_the_port_battery_fires_at_a_player_off_its_beam_and_the_rear_missiles_stay_closed` keeps its assertion (closed outside EMERGENCY).
20. `test_a_rail_closes_a_vent_and_an_emp_cuts_a_rear_salvo` (both harnesses; review round 1, finding 7) — (a) in VENT, `suspend_ai()`: both vents
    locked again, every part light and the hull light OFF, `mover.max_speed` back to 140; (b) in EMERGENCY with the Missiles mount in TELEGRAPH (player
    behind), `apply_emp(2.0)`: the mount is back in SCAN, no rocket for the window, the hull light and every weapon-part light OFF; control: the pod
    telegraphs again after the window. In Assault the hull is held inside the view for (b), as in rows 16 / 16b (review round 2, R2-2).
21. The t4 row `test_a_bullet_through_each_exposed_edge_hits_that_part_and_the_hull` frees the cannon shield before its cannon shot (Unchanged on purpose).
22. Conditional (only if row 15 shows a self-hit): the launcher-guard rows in `test_enemy_rockets.gd` (Own rockets).

Boundary cases: rows 7 (exact band edges, repair), 6 / 2 (the started burst against none started), 13 (front control), 14 (fired before / never after),
16 (R = 1.0 / 1.3 against 3.5, with the bypassed-gate control), 16b (the `can_fire` clause alone), 10 (shield up / broken; arc in / out).

## Risks
- **Gate time** (allotment 2.5 s; escalation past 3.75 s). Estimate ≈ 13 800 hand-ticked steps (the 50 s emergency run ×2 is 6 000 of them) at ≈ 80 µs
  ≈ 1.1 s, plus ≈ 16 real-physics shots at 16× and a dozen worlds ≈ 0.5 s: ≈ 1.6 – 1.9 s. Levers if over: share the front control and the chase's first
  seconds with existing runs, trim per-tick logging (rule 3). Never a shorter window than the plan's (30 s after destruction, 60 s of emergency).
- **Assault geometry:** a boost carries the hull out of the fixed view and the corridor filters its velocity, so the Assault emergency / closure rows
  hold the hull inside the view and assert cadence and the commanded boost direction there; the displacement "away" is an Open Space assertion only
  (review round 2, R2-2 / R2-3).
- **Pool exhaustion** in long synchronous rows (gun rounds never recycle without a frame): rows count phase entries (TELEGRAPH / FIRE), which a dry pool
  does not hide, and only count rounds where the pool is fresh.
- **Self-hit found:** the launcher guard above (a change to every rocket launcher), with its real-physics rows, logged. At rest its radius is
  today's arming radius; the look-ahead only closes the HitBox earlier on a rocket's way back, so every Ph5 / Ph8 arming row keeps its numbers.
- `BeamBehavior.tick()` outside a physics frame queries `direct_space_state`; if Godot refuses it, the row uses t2's `BeamDriver` on real physics at 16×.

## Out of scope
Art and wreck textures (t9); the Carrier (t6 – t8); the deadline rocket term and level-1 rows (t11); hub placement (t10); docs beyond the entity doc, the
CLAUDE.md line and DECISIONS (t13); enemy beams on parts (Ph18 / 19); ship-mounted EMP (Ph18).

## Review round 1 — what changed (4-review.md, CHANGES_REQUESTED)
1. t4's reachability row frees the cannon shield before its cannon shot (Unchanged on purpose; row 21); logged as a t4-gate change.
2. The self-hit fallback is the rocket-side launcher guard (the HitBox closed inside the launcher's look-ahead radius on every tick), not §2.5's
   hit-side exemption, which cannot stop the hurtbox-side damage; row 15 asserts "open HitBox overlapping"; the conditional real-physics rows (22).
3. The emergency run's player is a pursuer for 0–20 s; the 800 px hold against the ≈ 770 px battery reach is recorded.
4. The shield-arc analysis is corrected: a corner leak of ≈ a third of evenly spread frontal shots, accepted and recorded.
5. Row 16 gains R = 1.3 (with a bypassed-gate control) and row 16b isolates the `can_fire` clause under a deferred expiry.
6. The heat run's phase B runs to 3.5 s past VENT's end.
7. Row 20 covers the rail-in-VENT and EMP-in-EMERGENCY hooks; the EMP-holds-VENT choice is marked (D) and logged.
8. The pod's every-other-boost cadence is recorded.

## Review round 2 — what changed (4-review.md, CHANGES_REQUESTED; written after the two-round cap, for a third round if the owner allows one)
- R2-1: the launcher guard keeps today's arming test and latch; a separate `_update_guard()` closes an armed rocket's HitBox only near a live launcher,
  with a look-ahead on the **closing** speed only (zero while the rocket recedes), written only on a change; the triggered-WARHEAD exception is stated.
- R2-2: the Assault reach / view relation is recorded (Reach in Assault); the Assault runs of rows 12–14, 16, 16b and 20(b) hold the hull inside the view
  and assert it; 16b's boost is 1 px/s and it gains the precondition "Missiles still in TELEGRAPH on the tick before expiry".
- R2-3: row 12 asserts the commanded boost direction (`emergency_boost_dir`) in both harnesses and the displacement in Open Space only; the Risks line
  is updated.

## Review round 3 (APPROVED) and as built (2026-11-16)
- **R3-1** is in: `test_emergency_closes_an_open_vent_for_good` (both harnesses) cuts the bar to 209 mid-VENT and asserts EMERGENCY on the next tick, both
  vents closed and dark, `max_speed` 140, and no vent reopened over 12 s of firing. A mutation that runs the exit hook on the clock exit only fails it.
- **R3-2 / R3-4 do not apply:** row 15 measured **no self-hit** (12 rockets in 60 s, no open rocket HitBox ever overlapped the hull rectangle; the closest
  open rocket was 109.3 px from the hull centre, the arming radius 109.2), so the launcher guard was not built and `enemy_rocket.gd` is untouched
  (row 22 not written). The guard design above stays the recorded fallback; R3-2's two points (the Carrier as a third launcher, the player-hugging
  pass-through) are added to it in DECISIONS should it ever be built.
- **R3-3** is recorded in the brain's header, ENEMY.md and DECISIONS (the EMERGENCY arc anchor outruns the 140 px/s hull; `ORBIT_MAX_LEAD` bounds it).
- **Test harness finding (not a design change):** `_tick()` runs the mover outside a physics frame, so `move_and_slide()` moves the hull by the last
  *idle* frame's delta before the mover reads its facing. After a 16× row restores its clock (or as a run's first test) that delta is large, and a boost
  then swings the hull off its broadside (first scratch run: the Assault pod never telegraphed, the chase launched 0 rockets). Every row with a boost
  whose facing matters starts with `await _fresh_idle_delta()`. The memoised runs are computed after that await in their first caller. **Run 6:** the
  helper first waited up to 5 frames for an idle delta ≤ 1/60 s, which left the rows to the machine (a forced 0.14 s delta fails 6 of them; the harness
  gate failed twice on that version); it now scales `Engine.time_scale` by 1e-6 until `after_each` thaws it, so the delta is ≈ 0 on any machine.
- Mutation checks run once (each red on the intended row only): the literal `is_committed()` VENT rule (row 6), the missile gate's budget clause
  (row 16), the `can_fire` expiry clause (16b), two-way bands (7), vents never opened (3, 8, 9), heat in CONTROLLED (1), no rear arc (13's control),
  no DISENGAGE `scan(0.0)` (16), the exit hook on the clock only (R3-1 row).
- The root frees the shield on `ModularHull.module_destroyed` (its `_on_module_destroyed`); `bind_mounts()` caches each part's `Light` and mounts;
  `StateLight.VENTING_COLOR` is `Color(1.0, 0.55, 0.1)`.
- **Run 7: the harness failures (runs 3, 5, 6) were the gate's output size, not a test.** The AI-Kanban worker runs the gate through Node
  `child_process.exec` with the default 1 MiB `maxBuffer`; this tree printed 1058270 bytes, mostly `[BulletPool] Pool exhausted` warnings with
  backtraces from hand-ticked shooters (607 in the suite, 217 from this file). `BulletPool.acquire()` now warns once per pool (repeats only under
  `--verbose`); gate output 413983 bytes. Recorded in DECISIONS (t5) and tests/README.md → Gate time → *Gate output*. No row changed.
