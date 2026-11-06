VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` (revision 1), `1-context.md`, `2-research.md` and `tasks.json`, checked against the code on `agent/auto-dev` @ `0933e1e`, `CLAUDE.md`,
`DECISIONS.md` (Ph7 / Ph8 sections and the Ph9 section the planner appended), and the Ph7 / Ph8 `REPORT.md`s.

**Verdict in short.** The design is sound and mostly built on what already exists: the lock sits on `PlayerBase` beside the Ph7 disruption, the jammer field is a
`HazardField` sampled by the body, the hijacked rocket follows the `EnemyRocket` / `ContactBlast` rules, and `EmpPulse` gains a defaulted trailing bitmask. The
three press seams, the `_step_disruption()` call order, the `_ARENA_*` box being exactly `projectile_world_rect()`, `EMPBlastModule`'s process-disable, the empty
`HazardInfo.disables_abilities`, `choose_kind()` / `force_next_kind()`, `world_anchored_x`, the free 67.5° bearing and the planet_approach column schedule all match the code.

Two problems block it. **(1)** The hijacked-rocket collision contract in "For every task" makes the rocket destroy itself the moment it is claimed. **(2)** Two of t8's
movement acceptance rows cannot pass with the plan's own speeds, and a third cannot fail. Both need a change to the plan text, because an unattended builder would
otherwise invent a fix (a new collision bit, or retuned speeds) or escalate. The minor findings are wrong numbers or vacuous rows that will cost a session if they
are left in.

---

## Blocking

### 1. The hijacked rocket's own HitBox hits its own shoot-down HurtBox, so it ends on the tick it is claimed
- **Severity:** blocking
- **Evidence:** `3-plan.md:43-46` (For every task), `:243-246` (§2.5). `assault/scenes/projectiles/missiles/homing/homing_missile.tscn` (HitBox `collision_layer = 32`,
  `collision_mask = 513`), `homing_missile.gd:63-66` (`_on_hit_box_area_entered` → `queue_free()` unless `ArmorQuery` deflects). `global/physics/collision_layers.gd:18`
  (`ENEMY_HURTBOX := 512`). The precedent guard is `enemy_rocket.gd:381` / `:392` (`if area.get_parent() is EnemyRocket: return`).
- **Tasks:** t4 (also t9's claim rows)
- **Problem:** Mask 513 = 1 + 512, so once the new HurtBox (layer 512) turns monitorable, the rocket's own HitBox reports it. `_hit_is_deflected()` returns false (a
  homing missile is neither armoured nor `deflects_hit`), and the rocket frees itself, as does any sibling homing rocket that touches it.
- **Fix:** In §2.5 and For every task, state that the homing missile's HitBox ignores any area whose parent is a `homing_missile` (its own HurtBox and other player
  rockets, the `EnemyRocket:381` rule), and decide whether an unhijacked player rocket may shoot down a hijacked one.
- **Detail:** The plan says "No new collision bit" and "HitBox keeps layer 32 / mask 513". That is right, but without the guard the fizzle, lure, dodge and cap rows all
  fail at once. The builder's obvious "fixes" are a new layer, which the plan forbids, or dropping 512 from the mask, which breaks the lure (R9.17). Sibling contact
  matters as well. A salvo flies 7 px apart (`RocketState._launch_homing`, spread 7.0), and a claimed rocket turning back would mutually destroy the unclaimed ones
  beside it. That makes "Cap: six eligible rockets → exactly 3 claims" and the in-flight row nondeterministic. An `EnemyRocket` HitBox (mask 640) will also start
  detonating on a hijacked player rocket. That is harmless, but say so.

### 2. t8's nose-cone row is physically unreachable, the route row cannot fail, and `break_speed` exceeds `max_speed`
- **Severity:** blocking
- **Evidence:** `3-plan.md:388-393`, `:403-405`, `:411-413`. The orbit angle advances at a configured angular speed (`missile_corvette_brain.gd:381`,
  `_orbit_angle += orbit_dir * config.orbit_angular_speed * scale * delta`). The mover clamps every non-boost request (`enemy_mover.gd:229`,
  `desired.limit_length(max_speed)`).
- **Tasks:** t8
- **Problem:** "Against a player turning to face it every 2 s, the fraction of ticks inside the ± 30° nose cone is under 25 %" needs the Hacker to clear 0.52 rad of
  bearing within 0.5 s of each snap, about 1.05 rad/s. The plan's fastest arc is `orbit_speed_ccw` 0.30 rad/s, and `max_speed` 230 at 720 px is 0.32 rad/s. So the
  Hacker spends at least 1.64–1.75 s of every 2 s in the cone, about 85 %. The "off the route" row (player cruising at 360 px/s) has no control. A 230 px/s Hacker
  cannot keep pace with a 360 px/s player, falls behind and leaves the forward cone with the penalty switched off too, so the row cannot fail. `break_speed` 300 is
  clamped to `max_speed` 230 (no `mover.boost()` is named), so a 300 px/s rusher always closes. "Returns to HOLD_ARC beyond 540" can then only happen once the rusher
  stops, which the row does not say.
- **Fix:** Restate the rows so that they can pass and can fail. For example: "after each snap the bearing leaves the cone within `nose_cone_deg / orbit_speed` + 0.5 s,
  and the direction chosen is toward the nearer edge (control: penalty off picks the random direction)". Give the route row a control in which the Hacker is fast enough,
  or a slower player (≤ 200 px/s), so that penalty-off fails. Either make BREAK_OFF a committed `mover.boost()`, or set `break_speed ≤ max_speed`, and say how the rusher
  stops.
- **Detail:** All three come straight from §2.19's starting values, which "keep them unless a row forces a change". Here the plan's own rows would force the change, so
  the builder would retune the Hacker blind (orbit speeds four times higher break "asymmetric arcs" and the 0.18 / 0.30 identity) or escalate. Fix it in the plan.

---

## Minor

### 3. Exact-tick unlock rows for the 1.5 s and 2.0 s timed locks fail on floating-point drift
- **Severity:** minor
- **Evidence:** `3-plan.md:178` ("locked for 90 ticks, unlocked on tick 90"), `:303` ("exactly 120 ticks"), `:467` (Disruptor "exactly 1.5 s (90 ticks)"). Summing
  `x -= 1.0/60.0` in doubles leaves 3.3e-16 after 90 steps from 1.5, and 2.1e-15 after 120 steps from 2.0, both > 0. 0.75 / 45 and 1.25 / 75 reach exactly 0. The Ph7
  rows deliberately assert "within a tick" (`tests/integration/test_player_boost_disruption.gd:449-451`, `test_enemy_mines.gd:1480-1486`).
- **Tasks:** t1, t5, t10
- **Problem:** With `maxf(0.0, x - delta)` the timed lock is still held on tick 90 / 120 and lets go one tick later, so the planned boundary rows are off by one.
- **Fix:** Specify the clock's end test with an epsilon (`<= 1e-6`, the `EnemyRocket` `- 1e-6` idiom) in §2.1, or assert "within one tick" as Ph7 does. Keep the
  exact T+44 / T+45 row for the 0.75 s field.

### 4. The Hijack Pulse dart's own lifetime numbers fail the sweep the plan adds it to
- **Severity:** minor
- **Evidence:** `3-plan.md:435-436` (`max_time` 1.5, `max_distance` 1400, `speed` 900), `:510-511`. `tests/integration/test_enemy_bullet_lifetime.gd:180-181`
  (`max_distance / min_fired_speed <= max_time`).
- **Tasks:** t9
- **Problem:** 1400 / 900 = 1.56 s > 1.5 s, so the row t9 is told to add is red on arrival. Relatedly, a rocket 650 px away flying directly away at 500 px/s is caught only
  after 650 / (900 − 500) = 1.63 s and 1462 px, past both caps, so a receding rocket at full `hijack_range` is never claimed.
- **Fix:** Set `max_time` ≥ 1.6 s (or `max_distance` ≤ 1350), and state in §2.11 that a rocket receding at range may outrun the dart (or size the caps for it). Also
  specify the tether order. A dart that emits `expired` straight after the claim is recycled by its `BulletPool` (hidden, process disabled), so the 0.3 s tether it owns
  never shows. Either emit `expired` after the flash, or give the tether to the rocket.

### 5. `assault_pulses_per_life` 2 can never bind inside a 9 s Assault budget
- **Severity:** minor
- **Evidence:** `3-plan.md:422-429`, `:442-443`, `:457`, `:608` ("the 2-pulses-per-life budget boundary").
- **Tasks:** t9
- **Problem:** The earliest second TELEGRAPH is `first_pulse_delay` 2.0 + TELEGRAPH 0.9 + PULSE 1.6 + cooldown ≥ 6.0 = 10.5 s, past `engage_seconds` 9.0, so the Hacker
  pulses at most once per Assault life and the "at most 2" row cannot fail.
- **Fix:** Either set the cap to 1 (and say so), or define an Assault cooldown that lets two pulses fit. Make the boundary row one that can be red, for example a shortened
  test config that would allow a third pulse.

### 6. The player's EMP Blast makes the new jammers untouchable while they keep jamming
- **Severity:** minor
- **Evidence:** `3-plan.md:311-313` (brainless structures keep the `PROCESS_MODE_DISABLED` path). `emp_blast_module.gd:59-67`. `hazard_field.gd:83-106` (the info stays
  registered and is refreshed only in `_physics_process`).
- **Tasks:** t6, t7
- **Problem:** A process-disabled jammer leaves the physics space (its body and HurtBox drop out, the bug S5 names) while its child `HazardField` stays registered with its
  last `disables_abilities` value. For 5 s the jammer cannot be shot but still locks the player, which breaks R9.9's "destroy it". The pulsed variant also freezes in
  whatever phase it was in.
- **Fix:** Give `JammingStructure` an EMP answer (EMP Blast skips it, or it switches its field off for the window: "EMP disrupts systems", R9.19) and add a row in
  `test_emp_blast_module.gd`. The Ph10 / Ph11 deferral for legacy enemies does not cover content this phase adds.

### 7. `EmpZone extends HazardField` contradicts `HazardField`'s composition rule and the plan's own jammer
- **Severity:** minor
- **Evidence:** `global/hazards/hazard_field.gd:1-2` ("The one script behind … a scene sets the exports and adds its sprite (composition, not four subclasses)").
  `3-plan.md:472`, versus §2.8's jammer, which composes a child `HazardField`.
- **Tasks:** t11
- **Problem:** The plan subclasses for one piece and composes for the other. The subclass also has to override `_physics_process` / `_enter_tree` and remember `super()`.
- **Fix:** Make `EmpZone` a `Node2D` with a child `HazardField` (kind `&"emp_zone"`) whose `phase_changed` it listens to, mirroring the jammer. If not, record why the
  subclass is preferred. Note that `test_sector_hub_patrol.gd::_element_radius()` matches `node is HazardField`, so either shape needs that helper checked (finding 11).

### 8. The "no hazard = bit-identical" row cannot be built as written
- **Severity:** minor
- **Evidence:** `3-plan.md:184` ("a spy on `Hazards.jammer_at` sees zero calls"). `global/hazards/hazards.gd` is a `RefCounted` of `static func`s.
- **Tasks:** t1
- **Problem:** GUT cannot double or spy a static function, so the row has no implementation.
- **Fix:** Assert the observable instead: lock state, signals and `ability_lock_fill()` are untouched over N ticks with `Hazards.count() == 0`, plus the existing
  bit-identity rows. Alternatively add a test-only static call counter, and say which.

### 9. A ProjectileLifetime expiry during a hijack bypasses `retarget_ended`
- **Severity:** minor
- **Evidence:** `3-plan.md:205-206` (`expired → queue_free`), `:229` (`retarget_ended` "on fizzle, blast, shoot-down or source death"). `projectile_lifetime.gd:76-80`. The
  precedent is `enemy_rocket.gd:432-437` (`_on_expired` ends the life through `_mark_done`).
- **Tasks:** t3, t4
- **Problem:** A rocket that has flown 4 s and is then hijacked hits `max_time` 6.0 inside its 2.5 s window. The lifetime emits `expired` straight to `queue_free`, so
  `retarget_ended` never fires and the areas are not closed deferred.
- **Fix:** In §2.5 say that t4 routes `expired` through an `_on_expired` that ends a live hijack (emitting `retarget_ended`, no blast) before the free, and add a row.

### 10. The level-1 Hacker window "before 95 s" overlaps planet_approach's 98.0 s peak, with no fallback
- **Severity:** minor
- **Evidence:** `3-plan.md:107` (P5: planet_approach at 7 of 7.5 at 98.0 s), `:532-537`. The Hacker's life is budget 9.0 + ≤ 1.6 + a measured exit.
- **Tasks:** t14
- **Problem:** A Hacker spawned after a 55–70 s jammer has drifted out (about 81–96 s) and still alive at 98.0 s makes 8 > 7.5. That leaves a spawn window of a few
  seconds (about 81–84 s), and the plan names no lever if it is infeasible. Earlier phases always pre-approved levers.
- **Fix:** State that the Hacker must be gone before 98.0 s. Give an ordered fallback, for example the Hacker before the jammer (a 40–50 s window), or a jammer spawned
  lower so it lives less. Say that t14 ends `Result: ESCALATE` rather than adding a frozen constant for asteroid_belt.

### 11. Hub placement ignores the existing Ph6 TacticalSpace sweep
- **Severity:** minor
- **Evidence:** `tests/integration/test_sector_hub_patrol.gd:880-922` (`_element_radius()`, `_space_clearance_violations()`: every TacticalSpace child clears every
  patrol's idle ring + `perceive_radius` by > 100 px and interactables by > 300 px). `3-plan.md:520-527`.
- **Tasks:** t13
- **Problem:** The EMP zone (a `HazardField`) in `TacticalSpace` must also clear every patrol, including the new draw-18 Hacker, by > 100 px past its idle ring and
  perceive radius, a constraint §2.16 does not list. A pulsed jammer (a `BaseEnemy`) there gets `_element_radius()` 0, so the existing sweep silently ignores its field.
- **Fix:** Name the Ph6 sweep in §2.16. Teach `_element_radius()` a `JammingStructure` (its field radius), or put the pulsed jammer under `EnemyContainer` like every
  other enemy, and keep sweep C for interactables.

### 12. t8 is not given §2.11, although §2.10 tells it to create the pulse config fields
- **Severity:** minor
- **Evidence:** `3-plan.md:405` ("the pulse fields of §2.11"). `tasks.json` t8 `planSections` is `["2.10", "2.15", "2.18", "2.19"]`.
- **Tasks:** t8
- **Problem:** The builder of t8 sees a reference to fields it cannot read.
- **Fix:** Either change §2.10 to "pulse fields are added by t9", or add `2.11` to t8's `planSections`.

### 13. t14's EMP-zone guard rows have no dependency on t11
- **Severity:** minor
- **Evidence:** `tasks.json` t14 `dependsOn: ["t9", "t7"]`; t11 depends only on t5. `3-plan.md:541-542` (guard: "no … EMP zone in an `ENEMIES_CLEARED` section, and no
  … EMP zone in any Assault section").
- **Tasks:** t14, t11
- **Problem:** t14 can run before `emp_zone.tscn` exists. Because the zone is never spawned by `WaveBuilder`, a wave-list guard over it is also vacuous unless it scans for
  the scene path.
- **Fix:** Add `t11` to t14's `dependsOn`, and say how the guard detects an EMP zone (scene path in the level's waves and `level_1.tscn`).

### 14. A counterplay from IDEAS §6.4 is dropped without being listed
- **Severity:** minor
- **Evidence:** IDEAS §6.4 Counterplay: "Force the hacker behind cover **or other enemies**". `global/enemy_ai/enemy_brain.gd:88-96` (`can_see_player()` through
  `TargetInfo.line_of_sight`: "a fighter body … never blocks"). `3-plan.md:657` (R9.17 → "LOS").
- **Tasks:** t9 (and §6 Out of scope)
- **Problem:** Only asteroids and wrecks block the pulse, so "behind other enemies" does not work, and §6 does not say so.
- **Fix:** Add a row to §6 (enemy bodies do not block LOS, the Ph6 rule, with the phase that may revisit it), or include enemy bodies in the pulse's LOS test.

### 15. The Disruptor's K lock defeats its own "newly launched" hijack, and the reasoning behind the placement rule applies to it
- **Severity:** minor
- **Evidence:** `3-plan.md:439` (Disruptor calls `apply_ability_lock` at PULSE start), `:29-34` (a lock refuses K). DECISIONS Ph9 *Conventions*: "Never place a Hacker
  inside or next to a jammer (a jammed player cannot launch, so the hijack would be moot)".
- **Tasks:** t10
- **Problem:** A 1.5 s lock during a 1.6 s PULSE means the player cannot launch for almost the whole window. The Disruptor protects the player from its own trick and
  stacks two EW effects, which F12 / §2.19 argue against.
- **Fix:** Either scope the Disruptor's lock to H only (a lock scope on `apply_ability_lock`), or apply it at PULSE end, or keep it and record in DECISIONS why the
  self-cancel is acceptable, since the variant is unplaced.

### 16. t5 edits `enemy_mine.gd` without the self-reference trap in its brief
- **Severity:** minor
- **Evidence:** `CLAUDE.md` ("Never name `EnemyMine` inside `enemy_mine.gd`"), `docs/architecture/PROJECT.md:407-408`. `3-plan.md:297` (t5 changes the EMP branch,
  `enemy_mine.gd:392`). Neither "For every task" nor §2.6 mentions the trap.
- **Tasks:** t5
- **Problem:** The `hostility`-dependent bitmask is exactly the kind of edit where `as EnemyMine` gets typed, and the resulting leak fails `verify.sh` with every test green.
- **Fix:** Add one line to §2.6 or to For every task's *Conventions kept*: "`enemy_mine.gd` never names its own `class_name`".

---

## Checked and fine (no finding)

- The **abilities and their seams:** H reaches modules only through the two `_input` loops (`player_ship.gd:236-258`, `player_fighter.gd:138-148`). K reaches only
  `RocketState._on_action` via `MovementController` (`movement_controller.gd:88-91`). `use_ability` has no other consumer. Open Space skips Boost Drive on H and fires it
  from Shift. Both ships call `_step_disruption()` first in their physics tick.
- **The homing missile:** it targets once at launch from `enemies`, is a child of the plain-`Node` `RocketState` (so `ContactBlast.spawn(get_parent(), …)` works), and its
  box equals `projectile_world_rect()` (x −164…1444, y −444…1164). In Open Space it really does die off-box.
- **EMP:** `EmpPulse.emit()` reaches only `player` today, and `test_emp_pulse.gd` stays green with the defaulted bitmask. `EMPBlastModule` reaches every `enemies` node,
  with no radius.
- **The hazard pieces:** `Steering.context_avoid` skips `avoid_weight <= 0` and returns `desired` unchanged. `HazardField`'s cycle and `_refresh_info()` are as described.
  `HazardInfo.contains()` is the centre-distance `<=` rule that `jammer_at` reuses.
- **The enemy hook:** `BaseEnemy._physics_process` is the only brain tick, and no brain-driven subclass overrides it. 12 brains own budgets (P1 is accurate and the
  DECISIONS change is recorded with a reason). `is_ai_driven()` excludes mover-less structures and railed enemies.
- **Gate time:** 212.4 + 22.4 = 234.8 s against 240 s, with the 238 s escalation rule. Ph7 / Ph8 used about half their allotments, so this is realistic.
- **Hub and level 1:** the 67.5° anchor (≈ (995, 2402)) clears the triggers, the pickups, the TacticalSpace elements and the defense site. A 425 or 825 world x clears every
  planet_approach column lit in a 55–81 s jammer life.
- **Research:** it has tradeoff tables for every part, and the sources it cites are used for what they are cited for. Audio is deferred to Ph17 as an owner choice with a
  seam, and jammer-linked groups go to Ph20 per the roadmap. Both are listed with reasons.
