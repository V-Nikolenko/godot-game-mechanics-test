VERDICT: APPROVED

(round 2; round 1 verdict was CHANGES_REQUESTED, kept below)

# Plan review: Enemy rework phase 6 (hazards, wells, anomalies, wrecks), round 1

Reviewed `3-plan.md`, `1-context.md`, `2-research.md` and `tasks.json` against the code at `a13c4d0` on `agent/auto-dev`,
`CLAUDE.md`, the idea's `DECISIONS.md` (Ph1 conventions, Ph4 and Ph5 as built, and the planned Ph6 section) and the Ph5
gate-time table in `tests/README.md`. I opened every file and line the plan relies on that is listed below.

The architecture holds up. A sampled registry, a drift term owned by the mover, context steering as a mover stage,
boost-as-commitment, a `HazardContainer` with "no container, no spawn" and opt-in projectile bending are all sound and
fit the house conventions. What blocks approval is narrower: two of the three "hazards as tools" designs do not work
against the code they modify (B1, B4), the third conflicts with the avoidance stage the same plan builds (B3), and every
runtime spawn ignores Godot's physics-flush rule in a way the planned hand-ticked tests cannot detect (B2). Each fix is a
plan edit, not a redesign.

---

## Blocking findings

### B1. The Ram's "drive the player toward a well" hooks into Assault-only code, while the only shipped well is in Open Space (t16)

- **Checked:** `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd:329-337` and `:343-361`, plus `_corridor()` at
  `:579-582`.
- **Problem 1 (Open Space):** `_choose_side()` is reached only when `rect.has_area() and config.assault_side_offset > 0.0`,
  and `_corridor()` returns `Rect2()` whenever the mover has no constraint. So in Open Space the APPROACH is a plain
  `mover.intercept(...)`, and `_choose_side()` never runs.
  - Plan §2.16 / §2.14 put the only shipped well in the Open Space hub, and none in level 1. So t16's behaviour would never
    fire in shipped content.
  - t16's "dual-mode" rows cannot pass in the `open_space` harness without new code that the plan does not describe.
- **Problem 2 (Assault):** `side` is an x sign, and the offset is `Vector2(side, vertical_side) * assault_side_offset`.
  That gives four diagonal stations round the player. "Prefer the side whose charge direction is within 30° of player →
  well" therefore usually has no qualifying side: a choice among four diagonals cannot guarantee a 30° cone.
- **Fix:**
  - Re-specify §2.14 as an approach-point bias that works in both modes. While a claimed well is within `well_use_range`
    of the player, the APPROACH target becomes `player + (player − well).normalized() * standoff`, which is the far side
    of the player from the well. In Assault, clamp it to the corridor the way `_predicted_aim` does.
  - LINE_UP's aim (Ram → predicted player) then points at the well.
  - Keep `_choose_side()` unchanged when there is no well, so the rng draw at `:352` and the 73.2 s row are untouched.
  - Assert the 30° cone on `charge_dir` in the `open_space` harness. Add an Assault row only where the clamp leaves the
    geometry feasible, and include one boundary row where the clamp makes it infeasible and the Ram falls back.

### B2. Runtime spawns happen inside a physics-query flush with no deferral (t11, t12, t15)

- **Checked:**
  - `assault/scenes/enemies/base_enemy.gd:226-240`: death runs inside `health.amount_changed`, which a bullet triggers
    from `HurtBox` `area_entered`.
  - `global/components/armor_plate.gd:107-154`: `broken` is emitted from inside `_on_hurt_box_area_entered`.
  - `global/components/contact_blast.gd:27-33`: "adding a physics body synchronously is refused ('Can't change this state
    while flushing queries')".
  - `assault/scenes/hazards/big_asteroid/big_asteroid.gd:63`: the in-house fragment spawn uses
    `parent.call_deferred("add_child", small)`.
- **Problem:** §2.9 instantiates a `Wreck` (a `CharacterBody2D` with `HurtBox` and `ContactHitBox` areas) "beside
  `_explosion_effect.explode()`". §2.13 spawns an `Area2D` fragment from `_on_plate_broken`. §2.10 creates a blast
  HitBox when an explosive wreck's HP reaches 0. All three normally happen inside a flush, and none is deferred.
  - The t11 rows are hand-ticked and kill through `health.decrease`, outside any flush, so they stay green.
  - Meanwhile every wreck from a real bullet kill in the live game fails to attach or logs an engine error.
- **Fix:**
  - State in §2.9, §2.10 and §2.13 that every runtime hazard spawn captures position, rotation and velocity immediately,
    then attaches deferred. Follow `ContactBlast.spawn` / `_attach`, which frees itself if the container is gone, or
    `big_asteroid.gd:63`.
  - Add one real-physics row (8× clock) to t11: a real player bullet kills a fixture enemy with `wreck_chance = 1`, and
    exactly one wreck appears in the container with no engine error.
  - Add the same kind of row to t15: a real rocket breaks a plate and one fragment appears.

### B3. Cover points sit inside the avoidance skirt that t4 builds, and t13/t14 are not given §2.4 (t4, t13, t14)

- **Checked:** plan §2.4 step 2, §2.11 and §2.12, the §2.2 profile table, and the tasks.json `planSections` for t13
  (`2.11, 2.8, 2.1`) and t14 (`2.12, 2.11, 2.8, 2.1`).
- **Problem:** both cover points are inside the owning ship's danger skirt round the wreck.
  - Sniper cover is at `radius + 50`, with Sniper `hazard_margin` 90 and avoidance 1.0.
  - Fighter cover is at `radius + 40`, with `hazard_margin` 60.
  - In that region `(R + margin) / d > 1`, so §2.4's `θ = asin(min(1, …))` saturates at 90°, plus one slot.
  - Every heading with any component toward the wreck is then masked (wreck `avoid_weight` 0.6, which is above the
    sniper's threshold of 0).
  - A ship arriving at its cover point is pushed away from it. Near the point, `arrive` gives a small desired speed and
    the speed floor is 35 %, so it can circle or chatter instead of settling. That threatens the Sniper's SETTLE gate
    (`sniper_brain.gd:477`) and the Fighter's "holds within `radius + 80`" row.
  - The t13 and t14 agents never see §2.4, so they cannot anticipate this.
- **Fix:** pick one of the following, write it into §2.4 / §2.11 / §2.12, and add §2.4 to t13's and t14's `planSections`.
  - (a) Put cover at `≥ radius + hazard_margin + 10`, and re-check that the line from the peek point still clears.
  - (b) Have the context stage skip the danger of the hazard whose `claimed_by` is the mover's own actor. This is a field
    read, not a new "ignore hazards" request API.
  - Either way, add a dual-mode row where a real Sniper or Fighter reaches and holds its cover point with t4's stage
    active.

### B4. The Fighter's cover hold does not fit `_derive_pass()` or the hold machinery (t14)

- **Checked:** `assault/scenes/enemies/fighter/fighter_brain.gd`:
  - `:515-583`: S is built as `anchor + b * standoff + l`, and `pass_bearing`, `pass_dir`, `pass_lane` and `_run_heading`
    are all derived from `b` and `l`.
  - `:648`: `_derive_pass()` is re-run on every APPROACH tick until `_latched`.
  - `:860-862`: "A solo fighter and the `forced_pass_kind` seam never" hold, because `_waits_for_window()` is
    `_in_squad()`.
  - `:846-855`: `_hold_station`.
- **Problem:** §2.12 says "move S to the wreck's far side … re-plan … and hold there (`_hold_station`) while
  `can_see_player()` is false, up to the existing hold limit".
  - Moving S without re-deriving `b` leaves `pass_dir` and `pass_lane` describing a run that no longer passes the player
    at the lane offset.
  - A solo fighter has no hold phase at all, and a squad member's hold is governed by the squad window, not by LOS.
  - Because `_derive_pass()` runs every tick, the claim and the moved S would have to be re-made or latched each tick.
  - None of this is specified, yet t14 is `medium` and runs on sonnet against a 1,650-line brain that is gated by the
    168-layout squad sweep.
- **Fix:** specify the following in §2.12, or mark t14 `large` so that it gets its own plan and review.
  - Re-derive `b = (cover_point − anchor).normalized()` and `standoff = |cover_point − anchor|`, so the run starts from
    cover and goes through the anchor with the existing lane rule.
  - Latch the cover choice and the claim until RUN_IN.
  - For a solo fighter, add a bounded "wait in cover" step: APPROACH arrives, then holds at most `cover_hold_max` while
    occluded. For a squad member, keep the window rules and only relocate S.
  - Say which of the 168-layout sweep rows must be bit-identical (all of them: there is no wreck there).

---

## Minor findings (fix in the same revision; none needs a redesign)

### M1. The Assault fighter's states run on `_process`, not after its physics, and Idle never clamps (t3)

- **Checked:**
  - `global/statemachine/state_machine.gd:15-17`: `_process(delta)` calls `current_state.process_physics(delta)`.
  - `assault/scenes/player/states/idle_state.gd`: no movement and no clamp.
  - `assault/scenes/player/player_fighter.gd:69-100`: dialog, knockback and engine-boost early returns.
- **Problem:** §2.3's premise ("its `_physics_process` (which runs before its state machine's child states) … the state's
  own `move()` and its hard-bounds clamp still run last") is wrong.
  - A hand-ticked test that calls `_physics_process` never runs a state.
  - In the live game, an idle player beside a well beyond the edge is dragged out of bounds.
- **Fix:**
  - Clamp to x [-100, 1380], y [-380, 1100] in `player_fighter._physics_process` immediately after the drift
    displacement.
  - Put the drift step after the `DialogPlayer.is_active` return, and say whether it runs during knockback and during
    `engine_boost_active`.
  - Optional: implement `hazard_speed_factor()` once in `PlayerBase` rather than in two overrides with the same formula.

### M2. A "bit-identical" pass-through with a far hazard can fail on −0.0 (t2)

- **Checked:** `global/enemy_ai/enemy_mover.gd:205-213`. With `turn_lerp` 0, facing is `heading.angle() −
  sprite_forward_angle`, and it is written directly.
- **Problem:** §2.2 step 5 always computes `v = v_self + d`. With a hazard registered (count > 0) but out of reach,
  `d == Vector2.ZERO`, and `(-5, -0.0) + (0, 0)` gives `(-5, +0.0)`. `angle()` then flips from −π to +π, so rotation
  differs by 2π.
  - Any `-Vector2(x, 0)` request produces −0.0.
  - The plan's own row "the same with a fixture well registered 2000 px away" can fail.
  - The same applies to the hub's permanent tactical space (t18): it keeps `count() > 0` during every existing hub test.
- **Fix:** add `d` (and subtract `_last_drift`) only when they are non-zero, and state it in step 5.

### M3. Brains read `actor.velocity`, which now includes drift (t2, t4)

- **Checked:** 37 `actor.velocity` reads in `assault/scenes/enemies/*/*_brain.gd`, including these state gates:
  - Ram LINE_UP `<= crawl_speed` (`ram_corvette_brain.gd:395`);
  - Sniper SETTLE `< settle_epsilon` (`sniper_brain.gd:477`);
  - Fighter `is_settled()` / braking (`fighter_brain.gd:382, :390`);
  - Razor feint stop (`razor_drone_brain.gd:448`);
  - the `arrive` / `hold_position` / `formation_slot` wrappers (`enemy_mover.gd:135, 163, 175`).
- **Problem:** inside a field these gates never pass and fall through to their caps. This matters for t16's Ram, which
  lines up near a well by design.
- **Fix:** either expose `EnemyMover.own_velocity()` (`actor.velocity − _last_drift`) and say which gates switch to it,
  or record in §2.2 and the DECISIONS Ph6 section that brain velocity reads include drift, and pin one row (Ram LINE_UP
  inside the pull ends at `line_up_cap`).

### M4. The Sniper's 15 % re-pick hysteresis contradicts "identical with no blocker" and is ill-defined (t13)

- **Checked:** `sniper_brain.gd:320-354` (re-pick at `_travel_cap`) and `:434`. The score
  `w_sep·… − w_travel·…` is often negative.
- **Problem:**
  - Applied generally, hysteresis changes picks with no wreck present.
  - "Beats by 15 %" has no meaning for negative scores.
  - "Keep the current point" fights the tier A/B relocation rule.
- **Fix:** restrict hysteresis to a current target that is itself a cover point, define it as an absolute margin (for
  example `0.15 * w_sep`), and keep the "same point as the control with no blocker" row.

### M5. The explosive-wreck blast is specified imprecisely, and its boundary row is ill-posed (t12)

- **Checked:**
  - `enemy_rocket.gd:16-24` and `:393-400`: the Ph5 rocket hurts enemies through its own HitBox on layer 32 and the
    player only through a `ContactBlast` on 256.
  - `contact_blast.gd`.
- **Problem:**
  - "A HitBox reaching both 128 and 512" is not how hurtboxes select hitboxes.
  - "Hurts at 110 px, neither at 111 px" is centre-distance language, but area overlap is shape-to-shape: a 20 px hurtbox
    at 111 px is hit.
  - DECISIONS Ph5 records "Friendly fire from blasts and beams is undecided (Ph8)", and this plan decides part of it
    without logging that.
- **Fix:** either deliver the blast as a sampled, distance-based pulse like hull stress (`Hazards.hurt_box_of`, which
  gives a centre-distance boundary), or spec the two areas (layer 32 for enemies, plates and asteroids; `ContactBlast`
  256 for the player) and state the boundary edge-to-edge. Log the friendly-fire slice in DECISIONS Ph6
  "Changes to earlier decisions".

### M6. The third plate's fragment can hit its own Ram (t15)

- **Checked:**
  - `ram_corvette.gd:138-153`: `_expose` is deferred, so the hull is unarmoured on the next step.
  - The enemy hurtbox mask is 1121, which includes 1024 (`base_enemy.gd` comment, `enemy_rocket.gd:19`).
- **Problem:** a fragment born at the plate overlapping the hull, with its contact box on 1024, deals 12 to the newly
  exposed Ram.
- **Fix:** have the fragment ignore its source (store `source` and skip it, or arm the contact after it has cleared the
  hull), and add a row.

### M7. Contact damage from a stationary wreck cannot happen as written (t10, t18)

- **Checked:**
  - `player_ship.tscn:212-216`: body radius 11, hurtbox 5. `player_fighter.tscn` is the same.
  - `test_contact_hitbox_geometry.gd:130-163`: the contact box must use the body's own shape and transform.
- **Problem:** §2.8 says "ships that ram a wreck are hurt". But the body stops the player about 6 px before its hurtbox
  can reach a box the size of the wreck body, and enemy hurtboxes meet the body at the slide margin. Only a wreck that
  drifts into a ship hurts it, so the hub's placed structures never do.
- **Fix:** state this (contact damage only from moving wrecks and debris) and phrase the t10 row that way, or drop the
  claim.
- **Related case:** a wreck spawned where an enemy died by contact (a ram or boost kill) appears on top of the player and
  hurts it at once. Give the contact box a short arming delay after spawn.

### M8. Missing ordering between tasks that edit the same files

- **Collisions:**
  - t8 and t17 both edit `enemy_ordnance.gd`.
  - t15 and t16 both extend `test_ram_corvette.gd`.
  - t11 edits every enemy `*_config.tres`, as do t13 (sniper), t14 (fighter) and t16 (ram), with no ordering between
    them.
  - t7 (a `clockwise` export, probably on `HazardField`) and t16 (`try_claim` / `release` on `HazardField`) can both edit
    `hazard_field.gd`.
- **Fix:** add `t17 → t8`, `t16 → t15`, and `t13`, `t14`, `t16 → t11`; also either `t16 → t7` or say where `clockwise`
  lives (on the anomaly scene's own script, not `HazardField`).

### M9. No gate sees wrecks or fields in the live level-1 run (t11, t17)

- **Checked:** `level_director.gd:170` and plan §4 ("they build their own containers without a `HazardContainer`").
- **Problem:** after t11, live cloud_descent has drifting wreck bodies (layer 1, collided by every enemy's
  `move_and_slide`) and avoidance danger in its exit paths. Its 73.2 s ram row has 0.40 s of margin
  (DECISIONS Ph4 open items). The deadline and density gates are calibrated without hazards, so they cannot see this by
  construction.
- **Fix:** add one row (t11 or t12) that replays cloud_descent with a `HazardContainer` and seeded kills of the fighters
  and rams at their attack points (wrecks at chance 1, the worst case). Assert that the enemy container empties inside
  `enemies_cleared_timeout`, or at least that a DISENGAGE exit past a wreck stays inside the measured exit bound. Budget
  it against t11's allowance.

### M10. `planSections` gaps

- **t13 and t14:** add `2.4` (see B3).
- **t7:** its first test row is a resistance-0 mover displaced by the swirl, which needs §2.2's drift/step order. Add
  `2.2`.
- **Every other task's list is sufficient.**
- **Top-level references:** t2/t4/t10/t11 use `4`, and t19 uses `1`, `3`, `5`, `6`, `7`. These rely on the matcher
  resolving `"4"` to `## 4. Test plan`. Ph5's tasks only referenced `N.M` sections. If the matcher is prefix-based on the
  number, this is fine. Otherwise use the opening words (`"Test plan"`, `"Risks"`, …).

### M11. Both harnesses are not stated for the anomaly and the Gravity Field (t7, t17)

- **Problem:** §4 claims "Both harnesses (R6.19): … anomaly (t7), Gravity Field (t17)", but neither §2.6's rows nor
  §2.15's say "dual-mode".
- **Fix:** mark t7's mover-swirl row and t17's "resistance-0.4 enemy slowed by 0.24" row as
  `use_parameters(["open_space", "assault"])`.

### M12. Smaller correctness notes

- **Swarm capture row (§2.5):** "a real Swarm Drone left in the core … stays within the core". The swarm's equilibrium
  is about 107 px (research §3.1), which is outside `core_radius` 90. Assert "stays within `damage_radius` (150) and
  dies".
- **Hub drifting debris (§2.16):** `debris_drift` at 20–40 px/s with `lifetime` 0 drifts away forever, and the clearance
  sweep only checks t = 0. Give placed debris speed 0 (or a bounded orbit), or a hub-only lifetime.
- **Assault wreck lifetime cap (§2.8):** at 60 px/s, crossing the 1608 px world rect (y −444…1164) takes up to 27 s. A
  wreck that spawns above about y −36 is cut by the 20 s cap while still on screen, and Assault has no fade. Raise the
  cap to cover the rect at `assault_drift`, or fade in Assault too.
- **The player's beam and wrecks:** `beam_behavior.gd:59-76` stops at any layer-1 body and damages only `enemies` and
  `asteroids`. A wreck therefore blocks the mining laser and cannot be cut by it. That is probably fine (it is cover),
  but say so in the wreck's `HAZARD.md`.

---

## Claims I checked that hold

| Claim | Checked at |
|---|---|
| The mover has one step, `request_velocity` / `add_nudge` / `boost` / `halt`, the constraint after the accel limit, and no external-force term | `enemy_mover.gd:75-123`, `:180-217` |
| The corridor filter's hard band removes outward velocity | `assault_corridor_constraint.gd:58-76` |
| Brain tick, then mover step | `base_enemy.gd:107-112` |
| `suspend_ai()` calls `halt()` | `base_enemy.gd:120-131` |
| A death hook can sit beside `explode()` | `base_enemy.gd:234-240`. No mover-driven subclass overrides `_on_health_changed`; only the station and turret do |
| Subclasses copy config onto the mover after `super._ready()`, so copying hazard fields in `BaseEnemy._ready()` is not overwritten | e.g. `ram_corvette.gd:47-78` |
| A plated Ram deflects any direct emit | `ram_corvette.gd:126-131` |
| `_on_plate_broken` is at `ram_corvette.gd:138`, and the plate sprite is still valid at `broken.emit` | `armor_plate.gd:145-153` |
| `LineOfSight` is mask 1 or 1024, bodies only, opt-in via `blocks_line_of_sight()`, at most 4 recasts | `line_of_sight.gd:16-49` |
| `TargetInfo.line_of_sight` is false with no target | `target_info.gd:119` |
| `EnemyBullet` HitBox is layer 256 / mask 128, every round inherits it, and only asteroids sit on 1024 today, so the `stops_enemy_rounds()` filter keeps asteroid behaviour | `enemy_bullet.tscn:27-29`, `rounds/*.tscn`, `big_asteroid.tscn:45` |
| The rocket impact mask is 640 | `dumb_rocket.tscn:41-42` |
| Open Space thrust 380, reverse 220, `max_speed` 420, boost 700; the boost sustain overwrites velocity; `engine_boost_active` returns early; `apply_knockback` is additive | `player_ship.gd:8-18`, `:322-453`, `:262` |
| Field arithmetic: 334 / 234 / 131 px/s², the 123 px thrust threshold, the terminal drifts | Recomputed |
| The config speeds in the capture table | The shipped `.tres` / config defaults |
| The bomber gravity bomb has no gravity today, and `_detonate` is a single exit | `enemy_ordnance.gd:172-189`, `:234-240` |
| Player missiles move from `rotation` | `homing_missile.gd:42-48`, `warhead_missile.gd:15-16` |
| Layer names | `project.godot:171-182`. Bit 12 is unused, so not allocating it is consistent with Ph1's "no layer until used" |
| `level_director.gd:170` polls the enemy container's child count | — |
| The hub's patrol rings are 1300 / 1500 / 1700 / 1900 px, and the 22.5° / 3200 px candidate is geometrically clear of them | Rough check: structures at about 2700 px are about 1300 px from the bomber anchor |
| The transparency gate sweeps `assault/scenes/hazards` | `test_entity_sprite_transparency.gd:85-90` |
| The geometry gates' rosters are hand lists that accept non-enemy scenes | `test_enemy_hurtbox_geometry.gd:70`, `test_contact_hitbox_geometry.gd:42` |
| Test helpers exist | `test_enemy_dual_mode.gd:57` `_tick()`, `test_level1_drone_exit.gd:60/72`, `tests/unit/test_line_of_sight.gd`, `tests/helpers/enemy_ai_harness.gd` |
| Gate time is about 198–202 s at the end of Ph5, and 29.5 s of allowances leaves about 8–12 s of slack | `tests/README.md` Ph5 table |

## What the plan gets right

- **The core model.** "Hazards are sampled by the body" with a static registry and an O(1) `count()` early-out:
  - it keeps the single-writer gate intact and needs no collision layer;
  - it is hand-tickable in both harnesses;
  - it costs nothing on the 186k-tick `test_fighter_squad.gd`.
  - The research weighs it honestly against a group scan and against `Area2D` overlap.
- **Avoidance.** Context steering as a mover stage keeps Ph1's rejection of weighted blending. "Committed run = boost =
  no avoidance" implements R6.8's rammer rule with zero brain edits. The profile threshold correctly notices that Fray's
  masking is scale-invariant.
- **The pull.** Drift-in-the-mover with exponential decay is the right answer to instant movers and boosts. Applying the
  corridor last means a well can never drag an enemy out of the band. The capture thresholds are designed, not
  discovered.
- **`HazardContainer`.** "No container → no spawn and no rng draw" is a clean way to keep every calibrated level-1 gate
  meaningful. Wrecks never enter the enemy container or `enemies`.
- **Contained rule changes.** Two-sided cover via a duck-typed `stops_enemy_rounds()` leaves asteroid behaviour
  unchanged. Projectiles bend without changing speed, so every lifetime gate's arithmetic stays valid.
- **Scope.** The scope check (S1–S14) is thorough. Every deferral (EMP zones → Ph9, capital wrecks → Ph19, Assault-placed
  wells → Ph15, anomaly variants and the active plate throw as owner options) names its reason and its phase. The
  requirement-coverage table is complete.
- **Tests.** Allowances per task, `before_all`-free hand-ticked rows, explicit boundary cases (`damage_radius + 1`, the
  0.5 cap, strongest-only, "no container → no draw", "same pick as the control") and the pass-through rows are the right
  kind of test.
- **Reuse.** The plan reuses `ProjectileLifetime`, `LineOfSight`, `ContactProfile._shove`, `StateLight`, `debris_1..6.png`
  and the laser-ray direct-emit precedent instead of reinventing them. A separate `Wreck` class rather than
  `AsteroidBase` is justified, because `AsteroidBase` joins `asteroids` and carries scoring fields.

---

# Plan review: Enemy rework phase 6 (hazards, wells, anomalies, wrecks), round 2

Reviewed revision 2 of `3-plan.md` (§8 response table included), `tasks.json`, `1-context.md`, `2-research.md`, the
idea's `DECISIONS.md` (the Ph6 planned section is consistent with the plan), and `CLAUDE.md`, against the code at
`b465af9` on `agent/auto-dev`. Every file:line below was opened.

**Verdict: APPROVED.** Every round-1 blocker's underlying problem is fixed, and the revision makes no architectural
regressions. What is left is two budget-arithmetic slips (N1, N2), which make the *Assault* half of the Ram's well
tactic and of the Fighter's cover phase unreachable and their Assault test rows unpassable, plus a handful of smaller
gaps. Each one is a value or a one-line rule that the building task can fix and verify, and each shows up as a red row
rather than as silently wrong behaviour. **N1 and N2 should still be applied before t16 / t14 start** (t14 gets its own
plan and review in any case; t16 does not start until t4, t6, t11 and t15 are done).

## Round-1 resolution

| # | Status | Checked |
|---|---|---|
| B1 | **Partly** | The Open Space station `S = P + (P − W)^·300` with a feasibility check, ticket, give-up and an untouched `_choose_side()` fixes the Assault-only hook (`ram_corvette_brain.gd:317-337`: APPROACH really is a plain `intercept` in Open Space). However, the new Assault gate can never pass, and the 0° Open Space row probably runs out of time (N1). |
| B2 | Resolved | `spawn_into` / `_attach.call_deferred` on the spawned node, defined once in §2.1, follows `contact_blast.gd:34-67` exactly. The explosive blast became a body-free `pulse_damage`. There are three real-physics rows (§4.3), and GUT 9.7.1 fails a test on engine errors (`addons/gut/gut_config.gd:57`, `error_tracker.gd:35`), so those rows can fail. |
| B3 | Resolved | §2.4 drops a LOS-blocking info that `is_claimed_by(actor)`. The Sniper claims at `_set_target_point()` and the Fighter at COVER entry, both before travelling. Reach-and-hold rows exist with avoidance active. t13 and t14 now list `2.4`. |
| B4 | Resolved | COVER is a separate appended phase (`fighter_brain.gd:60`, and no `Phase.size()` / `keys()` use), so `_derive_pass()` (`:640-662`), the latch and `_tick_hold` (`:887-944`) are untouched. It covers solo fighters and LEAD only, the sweep stays bit-identical, and t14 is now `large` with its own review. The Assault budget gate is broken separately (N2). |
| M1 | Resolved | Drift and clamp sit inside `player_fighter._physics_process` after the dialog and knockback returns and the engine-boost branch (`player_fighter.gd:69-100`). `PlayerBase.hazard_speed_factor()` is implemented once (both ships extend `PlayerBase`). Nit N7: dash already clamps. |
| M2 | Resolved | §2.2 steps 5 and 8 skip a zero drift. The −0.0 row and the 2000 px far-well row were added. |
| M3 | Resolved | `own_velocity()` is in §2.2. The named gates exist at `ram_corvette_brain.gd:395`, `sniper_brain.gd:477`, `fighter_brain.gd:382/390/737`, `razor_drone_brain.gd:448`. There is a Ram LINE_UP-in-a-well row, and the rule is logged in DECISIONS Ph6. |
| M4 | Resolved | Hysteresis applies to cover only, with an absolute margin `0.15·w_sep`, plus a no-wreck row. `_travel` re-pick is at `sniper_brain.gd:349-353`. |
| M5 | Resolved | `pulse_damage` uses centre distance with `≤`. A plated Ram deflects it (`ram_corvette.gd:125-130`). The friendly-fire slice is logged in DECISIONS Ph6. |
| M6 | Resolved | `source` + `source_clear_radius`. Enemy hurtbox masks really are 1121 at runtime: `DefenseProfile.apply_to()` overwrites the scene masks of 65 / 97 (`base_enemy.gd:79-80`, `defense_profile.gd:38-54`), and no enemy scene authors a profile. |
| M7 | Resolved | Contact damage is stated to come only from moving wrecks, plus a 0.6 s arming via `monitorable` (the HurtBox is the side that detects: `hurtbox_component.gd:39-49`). See N5 for the same geometry applied to the explosive fuse. |
| M8 | Resolved | The dependencies t17→t8, t16→t15, and t13/t14/t16→t11 are all present in `tasks.json`. `hazard_field.gd` belongs to t1 only. |
| M9 | Resolved | The exit guard extends the real 66 s replay in `test_level1_fighter_exit.gd` (header `:1-31`) with a container, chance 1 and mid-corridor kills. Its levers are pre-approved. |
| M10 | Resolved | All 96 `planSections` entries (27 distinct headings) match a heading by number or opening words (`grep -n '^#' 3-plan.md`). `"2.1 HazardInfo"` avoids prefix-matching 2.10–2.18. |
| M11 | Resolved | §2.6 and §2.15 rows are marked dual-mode. §4.4 lists every dual-mode row. |
| M12 | Resolved | Swarm row asserts within 150. Hub debris has `speed` 0. The Assault x-only inheritance and the 30 s cap (≥ 26.8 s crossing) are in place. The beam note goes in `HAZARD.md`. |

**Count: 15 resolved, 1 partly (B1), 0 not resolved.**

## New findings

### N1 (minor, apply before t16). The Ram's Assault well gate is unreachable, and the 4.0 s give-up is too short for the 0° row (t16)

- **Checked:** `ram_corvette_config.tres` (`engage_seconds = 4.0`, `cruise_speed = 280.0`, `acceleration = 500.0`);
  `engagement_budget.gd:50-53` (`remaining() = seconds − elapsed`); `ram_corvette_brain.gd:137-142` (`budget.update` runs
  before the dispatch); plan §2.14.
- **Problem (Assault):** §2.14 takes a ticket in Assault only while `budget.remaining() >= well_setup_max +
  line_up_cap`, which is 4.0 + 0.5 = 4.5 s. The Ram's whole budget is 4.0 s, so the condition is never true.
  - The Assault "feasible" row (`charge_dir` within 30° of P→W) cannot pass.
  - The Assault boundary row passes only vacuously.
- **Problem (Open Space, 0° row):** with the Ram spawned 900 px from P on the well side and W 350 px from P, the straight
  line to S passes through the well's centre.
  - The Ram (threshold 0.5) has to go round a radius of roughly 420–480 px. That is about 1,500–1,650 px of path at
    280 px/s, which takes about 5.5–6 s, against the 4.0 s give-up.
  - It sets `_well_refused` and charges from wherever it is, so "each time `charge_dir` within 30°" fails at 0°.
- **Fix:**
  - Gate the Assault ticket on what is actually needed:
    `remaining() >= line_up_cap + ATTACK_GATE_MARGIN + |pos − S| / cruise_speed()`.
  - Make the give-up distance-based, for example `|pos − S|₀ / cruise_speed() · 1.5 + 1.0 s`, or give it a separate
    Open Space value (about 8 s).
  - Alternatively, make the tactic Open Space-only this phase (Assault has no wells until Ph15) and drop the Assault
    rows. Either way, re-check the 0° row's timing.

### N2 (minor, apply in t14's own plan). Fighter COVER can never start in Assault (t14)

- **Checked:**
  - `fighter_config.tres:42` (`engage_seconds = 6.0`).
  - `fighter_brain.gd:279` (`budget.update(delta)`), which runs before the `match phase` at `:285-294`.
  - Plan §2.12 (`cover_min_budget` 6.0 s).
- **Problem:** the budget is already below 6.0 on the first tick, so `budget.remaining() >= 6.0` is never true on an
  APPROACH tick, and COVER is Open Space-only in practice.
  - The dual-mode row "a solo fighter enters COVER, reaches C and holds" fails in the `assault` harness.
  - The owner summary's "a lone Fighter … waits behind one" never happens in level 1, which is where the wrecks are.
- **Fix:** derive `cover_min_budget` from what a cover-then-pass needs (`cover_hold` + lead-in + run, for example
  4.0 s, cross-checked with `run_budget_slack()`), or declare COVER Open Space-only and drop the Assault rows. State the
  result in §2.12.

### N3 (minor). Cover claims are released on too few exits (t13, t14)

- **Checked:**
  - `sniper_brain.gd:325-353` (`_set_target_point`, travel-cap re-pick).
  - `:51` (RELOCATE, IDLE, RETURNING exist).
  - `fighter_brain.gd:430-445` (`_tick_anchor_idle` moves any non-bursting phase to IDLE, NOTICING or RETURNING).
- **Problem:**
  - The Sniper releases only on BREAK_CONTACT and DISENGAGE. A re-pick or relocation to a different point keeps the old
    wreck claimed, and so do IDLE and RETURNING in the hub. A second sniper is then refused a wreck nobody is using,
    until the claimer dies.
  - The Fighter's §2.12 release list omits the anchor-idle exits from COVER.
- **Fix:** release the previous claim in `_set_target_point()` whenever the new point is not the same cover. Release it
  on every exit from COVER, done in `enter_phase()`. Add one row each.

### N4 (minor). The alive cap can retire the hub's placed structures (t11, t18)

- **Checked:** plan §2.9 (the cap counts "the container's children in group `wrecks`") and §2.16 (placed structures are
  `Wreck` scenes, and the `TacticalSpace` parent is unspecified).
- **Problem:** if `TacticalSpace` is placed under the `HazardContainer`, the three structures have the lowest sequence
  numbers. They would be the first retired once five more wrecks exist in the hub.
- **Fix:** the cap counts only runtime-spawned wrecks (`lifetime > 0`, or a flag set by `spawn_into`). Placed structures
  are never retired. Add a t18 row.

### N5 (minor). The explosive wreck's touch fuse uses the geometry M7 showed cannot touch (t12)

- **Checked:**
  - `player_ship.tscn:212-216` (body radius 11, hurtbox radius 5).
  - Every enemy `ContactHitBox` has mask 0, so hitboxes do not monitor.
  - Plan §2.10 ("1.0 s after a ship's hurtbox first overlaps its armed contact box").
- **Problem:**
  - A ship stopped against a stationary explosive wreck never overlaps the wreck's body-sized contact box. An Open Space
    explosive wreck from a ship that died at rest can therefore never be touched off.
  - The plan also does not say what detects the overlap.
- **Fix:** fuse on a proximity ring, for example body radius + 16 px. Use a polled `get_overlapping_areas()` on a small
  monitor area (mask 128 | 512) or a centre-distance check against groups `player` / `enemies`. Phrase the row as "a ship
  stopped against it detonates it 1.0 s later".

### N6 (minor). `pulse_damage` ignores the Assault barrel-roll i-frame, and the "rails are untouched" wording (t1, t6, t12)

- **Checked:** `dash_state.gd:101-104` (a side roll sets `HurtBox.monitoring = false` as its invulnerability),
  `player_base.gd:106-119`, `hurtbox_component.gd:4`.
- **Problem:**
  - A direct `received_damage.emit` bypasses the roll, so hull stress or a wreck blast hits a rolling player.
  - Each 0.5 s stress pulse also costs one shield charge (`consume_one()`), which should be a stated choice.
  - "For every task" says rails and legacy enemies are untouched, but `pulse_damage` hits every node in `enemies`.
- **Fix:**
  - `pulse_damage` skips a hurtbox whose `monitoring` is false.
  - State the shield-charge cost in the well's `HAZARD.md`.
  - Reword the rule to "rails and legacy enemies are never *moved* by a hazard; environmental damage hits them".

### N7 (nit). `dash_state.gd` already clamps (t3)

- **Checked:** `dash_state.gd:137-140`.
- **Problem:** §2.3 says dash "has none today", but the clamp is already there.
- **Fix:** none needed. The implementer only applies the speed factor there.

### N8 (nit, for t14's own plan). A LEAD in COVER dissolves the pincer

- **Checked:**
  - `fighter_brain.gd:925-944`: a FLANK's `_wait_time` runs while `_lead_holding()` is false, and it goes at
    `flank_wait_max`.
  - `fighter_config.tres:45` (`flank_wait_max` 2.0).
- **Problem:** with `cover_hold` 1.2 s plus the travel to C, the hub pair's FLANK goes alone almost every time its LEAD
  takes cover.
- **Fix:** either pause the FLANK's wait while its LEAD is in COVER (still bounded by `cover_max`), or record the
  behaviour as accepted in DECISIONS.

### N9 (nit). t8 complexity, and t16 `planSections`

- **t8:** marked `small`, but it changes four movement models (`EnemyRocket._heading`, `EnemyOrdnance` bombs, and two
  player missile scripts) and adds a new per-family test file. `medium` is more realistic.
- **t16:** its "wall of fixture wrecks" give-up row needs §2.8. Either add `2.8`, or let the row use any hazard fixture.

## Other checks that hold

- **Gate time:** the allowances sum to exactly 35.5 s (t1–t19), against the README's "198–202 s at the end of Ph5". The
  recover-first rule at 232 s is in "For every task".
- **Context steering and the single-writer gates:** context steering, drift and slow live in `EnemyMover.step()`. Brains
  only read, so the single-writer gates are unaffected.
- **Signal declarations:** the new signals are declared with their arguments (`phase_changed(phase: int)`,
  `stressed(count: int)`).
- **Collision layers:** no new collision bit is used. `EnemyBullet` gaining 1024 uses an already-named layer.
- **Enemy rounds and wrecks:** an `EnemyBullet` round expires on any `area_entered` today (`enemy_bullet.gd:44-45`). The
  duck-typed `stops_enemy_rounds()` filter therefore really is what keeps asteroid behaviour unchanged.
- **Placement of the death hook:** `_maybe_leave_wreck()` beside `explode()` (`base_enemy.gd:226-240`) is reached by
  every mover-driven enemy, and `_brain.rng` is per brain. A draw on a dying brain cannot shift any other seeded
  sequence.
- **DECISIONS Ph6 (planned):** matches the plan, and lists every change to earlier decisions: bit 12, context steering,
  Gravity Field moved from Ph7, rounds stopping on wrecks, the friendly-fire slice, and `own_velocity()`.
