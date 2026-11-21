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

---

# Round 2

VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` revision 2 (its §8 answers round 1), `tasks.json`, `1-context.md`, `2-research.md` and the DECISIONS.md Phase 9 section, checked against the code on
`agent/auto-dev` @ `e181792`. The headings in `tasks.json` `planSections` all exist (`grep -n '^#' 3-plan.md`). Every component the plan names exists with the API it uses:
`AssaultDrift` (60 px/s), `StateLight`, `AnchorIdle`, `EngagementBudget`, `LineOfSight.clear`, `ContactBlast.spawn`, `EmpRing.spawn`, `BulletPool`, `Steering.turn_toward` /
`break_contact` / `orbit`, `EnemyMover.boost` / `halt`, `HazardField.phase_changed` / `phase()` / `phase_progress()`, `_section_has_scene()`,
`test_ph8_static_members_clear_every_lit_column`, `ph8_exit_keys.gd`.

**Verdict in short.** Fifteen of the sixteen round-1 findings are resolved in the text and in the code they depend on. The self-hit guard, the 1e-6 clock, `HazardField.suppress`,
the composed `EmpZone`, the level-1 constraints and options, and the dependency fixes are all correct. One blocker remains, in the same t8 rows round 1 blocked on. The restated
nose-cone and route-cone rows ignore the Hacker's own acceleration (260 px/s²). When the Hacker is orbiting toward the far edge, which is exactly the case the penalty exists for
and the case the row's own control is built around, it cannot reverse and leave inside the bound. At these numbers the "nearer edge" rule also gets it out *later* than doing
nothing. The minor findings below are wrong or knife-edge numbers and small contract gaps.

## Round-1 findings

| # | Sev. (r1) | Status | Evidence |
|---|---|---|---|
| 1 | blocking | **resolved** | §2.5 / For every task: `if _done or area.get_parent() is homing_missile: return` before `ArmorQuery`. It is the exact `enemy_rocket.gd:381` shape (same `Area2D` base, a self-named `class_name` that is leak-free in the `EnemyRocket` precedent). Real-physics salvo rows at 2 / 10 / 30 ticks fail without it. The warhead side is still open (new M3). |
| 2 | blocking | **partly** | `break_speed` is fixed: `mover.boost` ignores `max_speed` (`enemy_mover.gd:224-229`), and `break_contact` doubles 0.25 → 0.5 (`steering.gd:201`), so radial ≈ 360/√1.25 = 322 px/s > 300. The rusher row (d_min ≈ 415 > 360) and its `min_range` 0 control (≈ 218 px < 340) both work. The route row now has a control. **The nose and route escape bounds are still unreachable** in the reversal case (new B1). |
| 3 | minor | resolved | `_tick_clock` with `<= 1e-6`. Checked in doubles: 1.5 − 90/60 = 3.3e-16, 2.0 − 120/60 = 2.1e-15, 0.75 − 45/60 = −6.2e-16, 5.0 − 300/60 = 1.3e-14, all ≤ 1e-6. The boundary row fails without the epsilon. |
| 4 | minor | resolved | Dart `max_time` 1.6 ≥ 1400/900 = 1.556. Receding-rocket limit stated, with a row (knife-edge, M5). Tether moved to the rocket; `BulletPool._recycle` hides and disables the dart, so this was needed. |
| 5 | minor | resolved | Cap 1 with the 10.5 s > 9.0 s arithmetic. The boundary row can fail (cap 2 → exactly 2). Its Open Space half is seed-dependent (M1). |
| 6 | minor | resolved | `answers_emp()` routes both EMP sources. The jammer's `apply_emp` → `HazardField.suppress`, and `_refresh_info` masks only `disables_abilities`, so the cycle keeps running (`hazard_field.gd:87-107`). A real press inside the field is refused, though (M4). |
| 7 | minor | resolved | `EmpZone extends Node2D` + child `HazardField`. `phase_changed` fires once per TELEGRAPH → ACTIVE edge (`hazard_field.gd:93-98`). `_element_radius()` is taught `EmpZone` first (`test_sector_hub_patrol.gd:880-894`). |
| 8 | minor | resolved | Observable assertions with `Hazards.count() == 0`. |
| 9 | minor | resolved | One `_finish(blasted)`. t3 wires `expired → _on_expired()`, and t4 turns it into `if not _done: _finish(false)`. `ProjectileLifetime` emits the host's `expired` duck-typed (`projectile_lifetime.gd:9-12`). Row added (but see M2 on how to fly a rocket for 5 s). |
| 10 | minor | resolved | §2.17 hard constraints 1–4, ordered options A–D, then `Result: ESCALATE`, never a frozen constant. Jammer life ≈ (1164 + 440) / 60 = 26.7 s from y −220, and C (y −120) is 3.3 s shorter, as stated. |
| 11 | minor | resolved | Pulsed jammer under `EnemyContainer`, sweep C, a "no jammer in TacticalSpace" row, the Hacker in `_patrol_groups()`. The anchor (995, 2402) is 2045 px from the site centre, ≥ 1520. DECISIONS.md still contradicts it in one line (M6). |
| 12 | minor | resolved | §2.10 says the pulse fields are t9's. |
| 13 | minor | resolved | t14 `dependsOn` includes t11. The source-scan guards each have a failing boundary. One runtime EMP path is uncovered (M7). |
| 14 | minor | resolved | §6 row (Ph19 / Ph14 with reason), plus a pin row (fixture enemy does not block, wreck does). |
| 15 | minor | resolved | Lock at PULSE end. A row shows a mid-PULSE salvo is still claimed. |
| 16 | minor | resolved | For every task (*Conventions kept*), §2.6 *Callers*, t5 description. `Hostility` is declared on `EnemyOrdnance` (`enemy_ordnance.gd:29`), so the unqualified form compiles. |

**15 resolved, 1 partly resolved.**

## New findings

### B1. The nose-cone and route-cone escape rows cannot pass when the Hacker must reverse, and at 260 px/s² the "nearer edge" rule is slower than no rule
- **Severity:** blocking
- **Task:** t8
- **Evidence:** `3-plan.md:435-442` (penalty), `:458` (`force_orbit_direction`: "the penalty still overrides it inside a cone"), `:472-478` (rows), `:461` (`acceleration` 260, no
  `braking`). `enemy_mover.gd:239-246`: a non-boost velocity changes at most `acceleration · delta` per tick, and `braking` applies only when `|desired| < |current|`, which is not
  the case in a reversal toward a 230 px/s request. `steering.gd:41-45` (`orbit`: seek an anchor at `clamp(4·dist, 60, max_speed)`). `missile_corvette_brain.gd:383-384`.
- **Problem:** The plan's "honest physics" (`:439-442`) counts tangential speed and forgets acceleration. A Hacker orbiting toward the **far** edge at 0.30 rad/s (216 px/s at
  720 px) needs 216/260 = 0.83 s just to stop, drifting about 7° further the wrong way. It then has to cover about 27° from rest. Simulated with the mover's exact rule (1/60 ticks,
  anchor clamp, 260 px/s², 230 px/s):

  | Range | Prior motion (far way) | Exit through near edge (penalty) | Exit through far edge (no penalty, keeps going) | Row bound |
  |---|---|---|---|---|
  | 720 | 0.18 rad/s | 2.15 s (wrong-way 0.50 s) | 3.88 s | 1.76 s |
  | 720 | 0.30 rad/s | **2.72 s** (wrong-way 0.83 s) | **2.33 s** | 1.76 s |
  | 520 (Assault) | 0.30 rad/s | 2.02 s (wrong-way 0.60 s) | — | 1.76 s |
  | route row, 720, player 100 px/s | 0.18 / 0.30 | 1.80 / 2.32 s | — | 1.67 s |

  Only a Hacker that starts at rest or already moves the near way passes (1.17–1.27 s). The matched main row (cone on, far direction forced, the mirror of the control) is therefore
  red on any implementation. The "net movement toward −30° over every 0.25 s window after the first 0.25 s" clause is red for 0.5–0.83 s of wrong-way drift. Even an unforced
  run is seed-flaky: reversals stay live between the four snaps, and roughly 1.3 s of outside time accumulates per 2.5 s cycle against a 3–6 s reversal clock, so a later snap
  often finds the Hacker moving the far way. A matching-time edge escape needs `acceleration` ≈ 900 px/s² (simulated 1.63 s). That is a 3.5× retune of a frigate that the builder
  would have to make blind under the "keep starting values unless a row forces a change" rule, which is the round-1 problem again. Worse, in the 0.30 rad/s case the penalty makes
  the Hacker leave the nose **later** (2.72 s) than the unpenalised orbit (2.33 s), so "always slides the short way" is the wrong rule at this acceleration.
- **Fix (plan text):**
  1. Choose the escape direction by **time to exit** given the current tangential velocity (or: "keep the current direction if already moving at ≥ `cone_escape_speed`·R toward
     either edge; otherwise the nearer edge"), or raise `acceleration` and state the new value.
  2. Restate both rows with an explicit initial state: steady orbit, a stated direction, reversals held off in the main row as in the control. Assert the **edge** of exit (sign)
     with a sim-derived time bound that includes the stop (for example ≤ 3.0 s at 720 px and ≤ 2.3 s at 520 px under the current numbers). Space the snaps beyond that bound
     (≥ 3.5 s, not 2.5 s). Drop the 0.25 s monotonic clause, or start it after `v/acceleration` + 0.25 s.
  3. Keep the control: penalty off, the same initial state, exits through the other edge, or is still inside at the bound.

### M1. The TELEGRAPH (and Disruptor) gate "player within 650 px" sits inside the Open Space held band 720 ± 90
- **Severity:** minor
- **Tasks:** t9, t10
- **Evidence:** `3-plan.md:493-494` (TELEGRAPH needs "the player is within `hijack_range` 650"), `:519-520` (Disruptor lock needs the same at PULSE end), `:431` (radius = 720 ±
  90). `missile_corvette_brain.gd:378` (`held_range() + range_drift * sin(...)`, period 6–9 s, `:53-54`). `2-research.md:295` intended 650 as a **rocket** reach ("inside the held
  range, so a rocket fired at the Hacker itself is claimable"), not a player gate.
- **Problem:** At 720 + 90·sin, the player is within 650 for only about 22 % of each 6–9 s drift period (about 1.3–2 s per trough). Open Space pulses phase-lock to the inward
  troughs. Rockets launched at the player (630–810 px from the Hacker) are mostly out of reach at launch, which weakens "newly launched" (R9.13) in the hub. The Disruptor's
  PULSE-end lock, 2.5 s after a trough start, usually finds the player beyond 650. The t9 boundary row "the same config in Open Space sees at least 3 [pulses in 20 s]" gets 2 or 3
  troughs in 20 s depending on `_drift_phase`, so it is seed-dependent with the default ranges.
- **Fix:** Give TELEGRAPH and the Disruptor lock their own `pulse_trigger_range` (≥ `preferred_range + range_drift` + margin, for example 870), and keep `hijack_range` 650 for the
  rocket claim (the research intent). Alternatively lower the Open Space `preferred_range` so that `preferred_range + range_drift ≤ 650`. Either way, have the boundary row's test
  config pin `range_drift = 0`.

### M2. Two t3 Assault lifetime rows are unreachable, and t4's "flown 5.0 s" row needs the same setup
- **Severity:** minor
- **Tasks:** t3, t4
- **Evidence:** `3-plan.md:224` ("one flying in-rect with no target expires at `max_time` 6.0; one at 2400 px from its origin expires", Assault harness), `:288` ("a rocket that has
  flown 5.0 s, then claimed"). The projectile world rect is x −164…1444, y −444…1164 (round 1), i.e. 1608 × 1608 with a 2274 px diagonal. `homing_missile.gd:44-52`: no target
  means straight flight at 500 px/s.
- **Problem:** A rocket with no target leaves the Assault rect within 4.55 s, so it can never reach 6.0 s. No displacement inside the rect reaches 2400 px, so that rule never trips
  in Assault. In Open Space a straight rocket hits 2400 px at 4.8 s, so it cannot "fly 5.0 s" either.
- **Fix:** Run the 6.0 s row (and t4's 5.0 s pre-flight) on a hurtbox-less `Node2D` target that the rocket circles or overshoots, so displacement stays small. Run the 2400 px row in
  Open Space. Assert only the rect expiry in Assault.

### M3. A player warhead is consumed by a hijacked homing rocket, contradicting "player rockets never hit each other"
- **Severity:** minor
- **Task:** t4
- **Evidence:** `warhead_missile.tscn:59-61` (HitBox layer 32 / mask 513), `warhead_missile.gd:33-36` (`queue_free()` unless deflected). `3-plan.md:263` ("a player rocket never hits
  another player rocket, hijacked or not"). The hijacked HurtBox is layer 512 / mask 64.
- **Problem:** Only `homing_missile.gd` gets the guard. A warhead salvo crossing a hijacked rocket frees itself on the rocket's HurtBox, while the hijacked rocket lives (its mask
  does not include 32). That happens near the player, which is exactly where turned rockets fly.
- **Fix:** Put the same `area.get_parent() is homing_missile` early return in `warhead_missile.gd::_on_hit_box_area_entered`, add a row (a warhead through a hijacked rocket: both
  alive), or record the exception in §6.

### M4. The jammer's EMP row presses EMP Blast from inside the field, where H is locked
- **Severity:** minor
- **Task:** t7 (and the owner summary, `:16`)
- **Evidence:** `3-plan.md:399` ("a real ship inside the local jammer, the player's `EMPBlastModule` activated"), `:33-34` (every H `try_activate()` is locked).
- **Problem:** Through the real seam that press is refused, so the row passes only by calling `try_activate()` directly. In play, EMP Blast can switch a jammer off only from
  outside its field (its reach is scene-wide, so that works), but the plan never says so.
- **Fix:** Say the row calls `EMPBlastModule.try_activate(player)` directly or fires from outside the field, add one row that an H press inside the field is refused, and state the
  "from outside" rule in R9.9 and the summary.

### M5. The receding-rocket row has a 1.8 px margin
- **Severity:** minor
- **Task:** t9
- **Evidence:** `3-plan.md:531` (a rocket 640 px away receding at 500 px/s is never claimed), `:526` (`claim_radius` 16, 1400 px cap). `projectile_lifetime.gd:73-78` (the distance
  rule is checked once per tick, after the host moved).
- **Problem:** The 1400 px cap trips at 1.556 s, when the gap is 640 − 400·1.556 = 17.8 px, only 1.8 px over the claim radius. A dart spawned from the dish a few px toward the
  rocket, or a one-tick eligibility lag, flips the result.
- **Fix:** Use the 650 px reach (gap 27.8 px) and spawn the dart at the hull centre, or state the spawn point and the margin in the row.

### M6. DECISIONS.md still puts the pulsed jammer in `TacticalSpace`
- **Severity:** minor
- **Task:** t13
- **Evidence:** `DECISIONS.md` Phase 9 → *Placement*, first bullet: "a pulsed jammer and an EMP zone in `TacticalSpace`". The next sentence of the same bullet, and `3-plan.md:624-626`,
  say jammers live under `EnemyContainer`, never in `TacticalSpace`.
- **Fix:** Correct the DECISIONS line. "For every task" tells builders that DECISIONS rules stand.

### M7. The Assault EMP guard misses runtime EMP mines from a `Minefield`
- **Severity:** minor
- **Task:** t14
- **Evidence:** `3-plan.md:662-666` (scan for `emp_zone.tscn` / `EmpZone` / instanced `emp_mine.tscn`). `minefield.gd:46` (`w_emp`), `sector_hub.tscn:279` (`w_emp = 0.15`). A placed
  field's mines are `Hostility.ALL`, so they become `TARGET_ALL` in t5.
- **Problem:** A `Minefield` with `w_emp > 0` in an Assault level creates enemy-reaching EMP mines at runtime without any `emp_mine.tscn` text in the level.
- **Fix:** Add "no `Minefield` with `w_emp > 0` in a level scene or script" to the source scan, with a boundary row.

### M8. Who builds the Disruptor hook is stated two ways
- **Severity:** minor
- **Tasks:** t9, t10
- **Evidence:** `3-plan.md:519` ("Disruptor hook (filled by t10)"), against `tasks.json` t9 ("Add the pulse config fields and the Disruptor hook (… applied at PULSE end)").
- **Fix:** Pick one. Suggested: t9 adds the field (0) and the PULSE-end call, and t10 adds the scene, config and rows. Both tasks list §2.11, so either works once it is said.

### M9. An enemy railed while EMP'd keeps its EMP state forever
- **Severity:** minor
- **Task:** t5
- **Evidence:** `base_enemy.gd:115-120` (`_physics_process` returns at once when `_ai_suspended or _brain == null`). `3-plan.md:314-320` (the EMP window counts down there).
- **Problem:** If `suspend_ai()` runs during the window (`EnemyPathMover`), the clock stops, and `EmpStatic` and `is_emp_disrupted()` stay on for good.
- **Fix:** Clear the EMP state in `suspend_ai()`, or tick the EMP clock before the early return. Add a row.

## Checked and fine (round 2)

- **Rusher arithmetic:** BREAK_OFF from about 1.0–1.2 s, the 3.0 s cap ends near the 4.0 s stop, d_min ≈ 415 px. The `min_range` 0 control reaches about 218 px.
- **Dart:** pure pursuit at 900 px/s cannot tunnel. Head-on closing is 23.3 px per tick, so some tick samples within 11.7 px < 16. A rocket fired *at* the Hacker and claimed at
  about 420 px turns on a 240–310 px radius and passes at about 310 px, so it does not hit its claimer by accident. 180° at 1.6 rad/s takes 1.96 s < 2.5 s.
- **Pool:** a `BulletPool` root child of the Hacker resolves the enemy container (`bullet_pool.gd:60-64`), and `BaseEnemy` frees on death at once (`base_enemy.gd:246-249`), so the
  darts are cancelled with the Hacker.
- **Collisions:** the player HurtBox mask is 1281 (no 32), so a hijacked rocket body never deals 100. An unhijacked rocket's HitBox still hits `EnemyRocket` HurtBoxes (512 / 96),
  so `test_enemy_rockets.gd` stays green.
- **Beam brains:** only `twin_laser_drone_brain.gd` and `laser_tender_brain.gd` reference `EnemyBeam` / `TwinLaserPair`, so the sweep row has exactly the two overrides to require.
- **Tasks:** dependencies match the file chains (`player_base` t1→t2→t5, `homing_missile` t3→t4→t5, `enemy_rocket` / `base_enemy` / `emp_blast` t5→t6→t7, hub test t11→t13,
  rosters t7→t10). Complexities and efforts are sensible (t10 small is right once M8 is settled). Each task's `planSections` holds what it needs.
- **Gate time:** allotments sum to 22.6 s, and 212.4 + 22.6 = 235.0 s ≤ 238 s, matching `tests/README.md:629`.
- **Hub:** anchor (995, 2402) checked, and the Hacker-vs-sector-jammer distance holds.

---

# Round 3

VERDICT: APPROVED

Review of `3-plan.md` revision 3 (its §8.2 answers round 2), `tasks.json`, `1-context.md`, `2-research.md` and the DECISIONS.md Phase 9 section, checked against the code on
`agent/auto-dev` @ `3a20d00`. I re-simulated the cone-escape rows with the mover's exact rule in a throwaway script: 1/60 ticks, `Steering.orbit` with the anchor correction
`clamp(4·dist, 60, 230)`, `limit_length(max_speed)`, `current.move_toward(desired, acceleration·delta)` (`enemy_mover.gd:225-247`, no `braking`), the `MissileCorvetteBrain`
`_orbit_angle` pattern (`missile_corvette_brain.gd:367-396`), a 2.0 s warm-up and a ±10° snap. Every `planSections` heading in `tasks.json` exists (`grep -n '^#' 3-plan.md`).

**Verdict in short.** All ten round-2 findings are resolved. B1 is fixed in substance. At 700 px/s² the "nearer edge" escape works, and the Open Space nose row's worst case is
1.70 s, exactly the plan's figure, against a 2.2 s bound. The Assault worst case is 1.63 s against 1.9 s. At 260 px/s² the main row fails as claimed (2.90 s / 2.02 s). The cone-off
controls fail their bounds. The leftover problems are test-fixture geometry inside the t8 rows plus three small contract or setup gaps. The worst is N1: as written, the Assault
re-snap in the 0.18 rad/s near-way case leaves the view, so the row's own "clamp never binds" assertion is red. A builder can fix it in place, and the cases still meet the
acceptance criteria. Round 2 graded unreachable rows like this (M2) as minor, so every finding here is minor. Apply N1 and N2 to the plan text before t8 starts if possible.

## Round-2 findings

| # | Sev. (r2) | Status | Evidence |
|---|---|---|---|
| B1 | blocking | **resolved** | `acceleration` 700 (`:460-463`, `:496`; it is the Support Ship's value, `support_ship_config.tres:11`). My simulation of the stated procedure at 700 px/s², exit times in s: nose at 720 px, 0.18 near / 0.18 far / 0.30 far = 1.27 / 1.55 / **1.70**, all through the near edge, bound 2.2. Nose at 520 px = 1.27 / 1.55 / **1.63**, bound 1.9. Wrong-way time 0.18–0.30 s, bound 0.5. Controls with the cone off exit the far way at 3.88 / 2.33 s, which is 40°/ω, so they are still inside at 2.2 s and at 1.9 s. At 260 px/s² the 0.30 far case takes 2.90 s at 720 px and 2.02 s at 520 px, so it fails, as claimed. The 0.25 s monotonic clause is gone. The re-snap and the route row have fixture problems (N1, N2), but the mover rule and the bounds are sound. |
| M1 | minor | resolved | `pulse_trigger_range` 870 gates TELEGRAPH and the Disruptor lock (`:538-548`, `:569-571`). `hijack_range` 650 is the rocket reach only. The cadence row has a 650 control, and the cap boundary row pins `range_drift` 0 (`:600-602`). The new ±1 px rows need a stated fixture (N4). |
| M2 | minor | resolved | `:225-230`. The hover on a hurtbox-less `Node2D` works: `homing_missile.gd:39-49` is direct pursuit with an instant turn, so it oscillates within one 8.3 px step. The 2400 px row is Open Space only, and t4 reuses the hover (`:296`). |
| M3 | minor | resolved | The `warhead_missile.gd` guard is in For every task (`:51`), §2.5 (`:268-270`) and t4, with a real-physics row that fails without it (`:295`). |
| M4 | minor | resolved | Three rows (`:413-418`): from outside through the real seam, refused inside, and a direct call documented as bypassing the seam. The rule is stated in the summary (`:17`), §2.8 (`:386-387`) and R9.9. |
| M5 | minor | resolved | 650 px start, dart launched from the hull centre (`:559-560`). Discretised, the cap trips on tick 94 with a gap of at least 23 px, more than 16. |
| M6 | minor | resolved | DECISIONS.md Phase 9 → *Placement* now puts both jammers under `EnemyContainer` and the EMP zone in `TacticalSpace`. |
| M7 | minor | resolved | `:724-730`. Today `w_emp` appears only in `minefield.gd`, `mine_layer_*` and `sector_hub.tscn:279`, not in `wave_builder.gd` or under `assault/scenes/levels/`, so the new scan starts green and its boundary rows can fail. |
| M8 | minor | resolved | t9 owns the field and the PULSE-end call, and t10 only adds the scene, config and rows (`:569-573`, t9 / t10 descriptions). |
| M9 | minor | resolved | `suspend_ai()` clears the window (`:329-330`), with a row that fails on the clock-in-brain-branch build (`:346-347`). `base_enemy.gd:115-117` confirms the early return. |

**10 of 10 resolved.**

## New findings

### N1. The Assault re-snap pushes the Hacker out of the view in the 0.18 rad/s near-way case
- **Severity:** minor (fix in place; the row is red as literally written)
- **Task:** t8
- **Evidence:** `3-plan.md:516` ("re-snapped 3.5 s after its first exit … exits again within the same bound", applied to both ranges) and `:518-520`. The plan says "every
  position it reaches in the row (≤ 75° from straight up at 520 px) is inside `view_rect().grow(-60)`: the view clamp never binds (asserted each tick)". The t8 acceptance
  criteria repeat "again after a re-snap 3.5 s later" with "view clamp never binding". `arena_camera.gd:102-104` gives a 1280 × 720 view.
- **Problem:** In the near-way case the warm-up carries the Hacker 20.6° from straight up. The near edge is 20° further the same way, so it exits at about 41°. It then keeps
  going the same way (reversals held) for 3.5 s at 0.18 rad/s (+36°), and the near-way re-snap exits 20° further still. Simulated, the body reaches 96° from straight up and the
  anchor 100°. The player sits 100 px above the bottom, so at 96° the Hacker is below the player and 17 px outside `grow(-60)`. The clamp binds, the per-tick assertion fails, and
  the clamped target changes the motion. The 0.18 far case reaches 82°, which is still in view but outside the stated 75° envelope. A run takes 8.0–8.4 s, close to the 9.0 s
  `engage_seconds`. A slower GUT exit inside the allowed bounds (2.0 + 1.9 + 3.5 + 1.9 = 9.3 s) would hit DISENGAGE mid-row.
- **Fix:** In Assault, re-snap **1.0 s** after the first exit (simulated maxima: body 70.5° and anchor 74.5° in the near case, 39° / 32° in the far cases, never closer than 40 px
  to the inset edge), or run the re-snap in Open Space only. In both cases set `engage_seconds` ≥ 30 on the test instance. Correct the "≤ 75°" sentence and the t8 acceptance
  criteria to match.

### N2. The route-row warm-up is ambiguous; on the natural reading the 0.30 rad/s case has no steady orbit and its margins are 3–4 ticks
- **Severity:** minor
- **Task:** t8
- **Evidence:** `3-plan.md:507-511` (warm-up: "2.0 s of ticks with the cone axis pointing away from the Hacker"; for the route row that axis is the player's velocity), `:521-523`
  (bound 1.8 s, simulated worst 1.33 s, controls 3.55 / 2.23 s), `:466-470`.
- **Problem:** The natural reading has the player moving at 100 px/s away from the Hacker during the warm-up. A 0.30 rad/s orbit around that player needs √(216² + 100²) ≈ 238 px/s
  > `max_speed` 230, so no steady orbit exists. The target angle runs ahead of the body by 8° after 2.0 s and 19° after 4.0 s, and the result depends on the warm-up length.
  Simulated for the 0.30 far case: main exit 1.60 s (bound 1.8), control exit **1.85 s** (still inside at 1.8 s by 3 ticks), wrong-way time 0.43–0.45 s (bound 0.5). With a 3.0 s
  warm-up both the main row and the control fail. The plan's own numbers come from a different reading: with the player **still** during the warm-up and moving only from the snap, I
  get 1.33 s main (the plan's value), 2.00 s control and 0.28–0.30 s wrong-way. Separately, every control figure in the table is about 0.24 s too high. A steady orbit covers the 40°
  to the far edge in 40°/ω = 3.88 s (0.18) or 2.33 s (0.30), not 4.12 / 2.57. So the nose control's real margin at 720 px is 0.13 s, not 0.37 s. That is still deterministic and
  still fails the bound.
- **Fix:** In the route row, the player is stationary during the 2.0 s warm-up (route cone inactive below 80 px/s) and starts moving at 100 px/s along the snapped axis on the
  snap tick. Correct the control column to 3.88 / 2.33 s (nose) and 3.32 / 2.00 s (route), so the builder compares GUT against the right numbers.

### N3. Nothing ends a jammer's `EmpStatic` overlay and `is_emp_disrupted()`
- **Severity:** minor
- **Task:** t7 (contract from t5)
- **Evidence:** `3-plan.md:380-381` (the jammer's `apply_emp` "shows the blue-white `EmpStatic` overlay built by t5; `is_emp_disrupted()` is true for the window"), `:325`
  (the EMP window is counted in `BaseEnemy._physics_process`). `base_enemy.gd:115-117`: `if _ai_suspended or _brain == null: return`, and a jammer has no brain.
- **Problem:** This is the same kind of bug as M9. Any EMP clock or overlay hide that t5 places in `_physics_process` never runs for a brainless jammer, so after one EMP Blast the
  overlay and `is_emp_disrupted()` stay on for good while the field re-lights after 5 s. No row checks the end of the jammer's window, only the field's.
- **Fix:** Derive the jammer's state from its field. Add `HazardField.is_suppressed()`, have `JammingStructure.is_emp_disrupted()` return it, and make the overlay's `visible`
  follow it (polled in the jammer's own process). Add to the t7 EMP rows: 5.0 s (±1 tick) after the Blast, `is_emp_disrupted()` is false and the overlay is hidden.

### N4. The ±1 px range rows need a stated way to hold the distance
- **Severity:** minor
- **Tasks:** t9, t10
- **Evidence:** `3-plan.md:589-590` (no TELEGRAPH at 871 px, TELEGRAPH at 869 px; a rocket at 649 px claimed, one at 651 px not), `:620` (Disruptor: a player beyond 870 px at PULSE end).
  `:544` (the Hacker keeps orbiting in TELEGRAPH / PULSE).
- **Problem:** A Hacker 871 px from the player heads for its 720 px orbit and is inside 870 px within about 4 ticks at 700 px/s². During the 1.6 s PULSE it moves up to about 370 px,
  and an unguided rocket moves 8.3 px per tick. Unless the fixture holds the distance, the 871 / 651 "never" halves turn into "not yet", and the 869 / 649 halves depend on tick order.
- **Fix:** State the fixture. Before every brain tick, re-place the stub player (with `velocity` zero, so the route cone stays off) and a `speed` 0 rocket at exactly that
  distance from the Hacker's current position. Alternatively, set `first_pulse_delay` so the cooldown expires on the measured tick and assert only on that tick. Use the same
  fixture for the Disruptor's "beyond 870 px at PULSE end" row.

### N5. The t14 title says the jammer comes first; the default option A sends the Hacker first
- **Severity:** minor
- **Task:** t14
- **Evidence:** `tasks.json:234` ("sends one small jammer and, after it has gone, one Hacker Frigate"), against `3-plan.md:712` (A: the Hacker in a 40–53 s wave, then the jammer)
  and the t14 description.
- **Fix:** Make the title order-neutral ("… one small jammer and one Hacker Frigate whose lives never overlap …").

## Checked and fine (round 3)

- **700 px/s² does not break the other rows.** BREAK_OFF uses `mover.boost`, which skips the acceleration step (`enemy_mover.gd:240`), so the rusher row is unchanged. In the
  `min_range` 0 control the Hacker is still capped at 230 px/s against a 300 px/s rusher. Higher acceleration only tightens the range-hold, reversal, hub-idle and Assault-clamp rows.
  Every exit is measured, not computed. The hub clearance sweeps use rings and radii, not acceleration.
- **Assault geometry of the first exit:** with the 2.0 s warm-up from straight up, every first exit stays within about 45° of straight up (anchor included) and at least 40 px inside `grow(-60)`. Only the
  re-snap (N1) leaves the view.
- **Pulse numbers:** the earliest second Assault TELEGRAPH is at 10.5 s, past the 9.0 s budget. The cap boundary config (0.5 / 1.0 s) gives about 5 pulses in 20 s in Open Space,
  so the "≥ 3" control holds. The cadence row's 650 control holds at 720 px with `range_drift` 0.
- **`HazardField`:** `phase_changed` fires only on a phase edge (`hazard_field.gd:93-98`), so the EMP zone emits once per TELEGRAPH → ACTIVE. `avoid_weight` is non-zero outside
  QUIET (`:181`). A `suppress()` mask on `disables_abilities` in `_refresh_info()` fits the existing structure.
- **DECISIONS.md Phase 9** matches revision 3: acceleration 700, the 870 / 650 split, the warhead guard, the outside-the-field EMP Blast rule, the `Minefield` scan and placement.
- **Tasks:** dependencies still follow the file chains in For every task (`:81-84`). t4 reaches t1 through t2. t14 depends on t7, t9 and t11, and t15 on t6, t12, t13 and t14.
  Complexities and efforts are sensible (t1, t4, t9 large / xhigh; t10 small). No task carries a `model` field, the same as every other epic's `tasks.json`, so the harness default
  applies. Each task's `planSections` holds what it needs, and every heading exists.
- **Gate time:** 22.6 s of allotments, 235.0 s projected, with the 238 s escalation rule unchanged.
