VERDICT: CHANGES_REQUESTED

# Plan review, round 1: Enemy rework phase 2 (Swarm Drone, Razor Drone, squad roles)

Reviewed `3-plan.md` (rev 1), `1-context.md`, `2-research.md` and `tasks.json` against the code on `agent/auto-dev`
(HEAD `e3ee6ce`), plus CLAUDE.md, DECISIONS.md, the phase-1 plan and the phase-1 REPORT.

Overall the plan is strong. Scope matches the epic and every out-of-scope item has a phase and a reason. Reuse is
right: `DefenseProfile` shape, `boost()`, `AttackController.fire_now()`, `BulletPool`, `TargetInfo`, the dual harness.
The research has real tradeoffs and relevant sources. The rename-then-evolve split (t9/t10), completeness guards
first (t1), and the swap-under-rails step (t14) before rails-off (t15) are the right ordering. I checked these claims
against the code and they hold: the cull rect ignores `offset` (D6), `free_after()` is read only by `EnemyPathMover`,
the BulletPool grandparent rule holds (D4), and there is no enemy audio anywhere, so the audio exclusion is justified.

Four findings block approval. Two are mechanisms that would not work as written: the blast and the overshoot curve.
The other two are a behaviour that no task owns and an oversized task.

---

## Blocking

### B1: The EXPLOSIVE blast can never hit the player as designed, and its tests would not notice (t3, t8)

Checked `assault/scenes/enemies/base_enemy.gd:160-169`, `global/components/explosion_effect.gd:1-6, 41-51`,
`assault/scenes/enemies/bomber/bomb.gd` and plan §2.3.

- **It is freed with its owner.** §2.3 makes the blast "a child `HitBox` … created by the profile".
  - Both detonation triggers kill the owner in the same call. Contact runs `health.set_health(0)`. Death runs
    `BaseEnemy._on_health_changed`, which calls `queue_free()` right away.
  - So the blast is freed at the end of the frame it was enabled in, before any physics step can report an overlap.
  - `ExplosionEffect` exists because of exactly this problem: it re-homes its particles into `actor.get_parent()`.
  - The plan calls death-while-armed "the blast's real gameplay value", and that is the case that can never land.
- **It is not positioned at the drone.** `ContactProfile` is a plain `Node`. An `Area2D` under a non-CanvasItem
  parent does not inherit the drone's transform, so a child blast sits at the canvas origin.
- **A one-physics-frame window armed with `set_deferred` probably never gets stepped.**
  - Enabling in frame N applies at the deferred flush.
  - The counter in frame N+1's `_physics_process` then queues the disable, which also applies before the server step.
  - The plan pins arm-while-overlapping for `set_armed()` (C5) but not for the blast.
  - `bomb.gd`, the only precedent, keeps its blast on for 0.15 s.
- **The §4 cases cannot catch any of this.** "Blast active for exactly one physics frame" and "death while armed
  detonates" can pass on flags and on the `detonated` signal while the player never takes damage.

**Required:**
- `detonate()` spawns the blast into the owner's parent at `actor.global_position`, following
  `ExplosionEffect.explode()`.
- The blast owns its own lifetime: N ≥ 2 physics frames on an accumulated counter, never `create_timer`, then it
  frees itself.
- t3/t8 add an integration case with a real player `HurtBox`:
  - an armed drone killed within `blast_radius` lowers the player's health by `blast_damage` (outside i-frames);
  - an unarmed drone does not;
  - `check-test-leaks.sh` stays clean.

### B2: `EnemyMover.max_turn_rate` does not bend velocity, so neither overshoot curves (t8, t10)

Checked `global/enemy_ai/enemy_mover.gd:169` (velocity = `move_toward`) and `:182-185` (the `max_turn_rate` cap is
applied to `actor.rotation` only).

- **Swarm OVERSHOOT (§2.7)** keeps "requesting the burst direction at `max_speed` while `max_turn_rate` bends the
  heading back toward the player". With that code the drone flies dead straight while only its sprite turns.
- **Razor OVERSHOOT (§2.8)**, "the mover's `braking` and `max_turn_rate` bring it round", brakes to a stop and then
  accelerates back. That is a stop-and-return, not IDEAS §5.1's "overshoots and curves away".
- **Root cause:** the misreading comes from `1-context.md:90` ("a capped turn rate produces the arc").
- **Why the tests miss it:** the §4 overshoot cases only check the state sequence (OVERSHOOT, one more pass, REJOIN),
  so they pass on a straight line.

**Required:**
- Specify a brain-side turn: the requested direction rotates toward the player by at most `turn_rate·delta` per tick.
  The natural home is a pure `Steering.turn_toward(current_dir, desired_dir, max_rate, delta)` added in t2 with unit
  tests.
- Add a case to each drone's spec: during OVERSHOOT, the velocity heading turns toward the player monotonically, by
  no more than `turn_rate·delta` + ε per tick, while speed stays above a floor (it does not stop).

### B3: Nothing owns the Swarm Drone's hub idle (t8, t16)

Checked plan §2.7 (the state list includes `IDLE`/`NOTICING` "via `AnchorIdle` around the squad anchor"), §2.11,
the §2.7 config table and `tasks.json`.

- **No owning task.** t8 does not depend on t7 (`AnchorIdle`) and its description never mentions idle. t16 says only
  "The Swarm's hub idle uses AnchorIdle with squad.engaged". So the behaviour falls between the two tasks.
- **No config.** The Swarm config table has no `perceive_radius`, `lose_radius`, `notice_time` or idle-orbit
  radius/speed.
- **The spawn-safety proof covers only the Razor.** §2.11's "900 − 200 = 700 > 450" uses Razor numbers. A Swarm
  squad idling on a "REAR-style" orbit at `rear_orbit_radius` 260 would sit at about 640 px, and its perception
  radius is unstated.
- **No tests.** Nothing in §4 covers squad-wide engagement: one member perceives, `squad.engaged` latches, and every
  member leaves idle. Nothing covers the Swarm's handover or its return to idle either.
  - This is R2.16/R2.22 behaviour that can regress.
  - "Nobody perceives at frame 0" only proves the start state.

**Required:**
- Assign the Swarm idle to one task: t16, or a new task after t7 and t8. That task needs a `dependsOn` on t7.
- Add the config fields and values.
- Redo the spawn-geometry inequality with the Swarm's own radii.
- Add test cases:
  - one member inside `perceive_radius` → all members out of IDLE within one tick;
  - hysteresis;
  - return to anchor beyond `lose_radius`;
  - the handover velocity bound.

### B4: t8 is really three tasks (t8, and t9/t10 via dependencies)

Checked `tasks.json` t8 and plan §2.7, §2.9 and §4. t8 currently covers:
- a new shared component, `StateLight`, which t10 also needs;
- a new enemy (scene, config, `.tres`, ENEMY.md, gate rosters);
- a brain of about 10 states (APPROACH, FORM×3 roles, WINDUP, BURST, OVERSHOOT, second pass, REJOIN, DISENGAGE,
  rails);
- squad integration (roles, attack window, side claims);
- about 16 dual-mode cases, each run in two harnesses.

That cannot be finished and verified in one session, even on the escalated track. A failure there would also stall
t9 through t17.

**Required:** split it, for example:
- **t8a `StateLight`** (small): the component and its unit test.
- **t8b Swarm solo cycle** (large): the scene, config and rosters; APPROACH, WINDUP, BURST, OVERSHOOT, second pass,
  EXPLOSIVE contact, the Assault budget exit and rail suspension, all as a squad of one.
- **t8c Swarm squad behaviour** (medium or large): FORM roles, the flanks' attack window, side claims, lead
  reassignment mid-burst, formation recovery and phase offsets.

Then:
- t9 depends on t8b (the rosters);
- t10 depends on t8a;
- t15 and t16 depend on t8c.

---

## Non-blocking (fix in the revision, or record in DECISIONS as accepted)

- **N1: The "< 10 s" budget derivation (§2.6, t6/t8) leaves out the last wave's spawn delay.**
  - `LevelDirector._wait_enemies_cleared` starts its clock on `waves_complete`, which `WaveManager._process` emits
    when the last wave *triggers*.
  - Cloud_descent's last wave (`level_1_director.gd:985`) spawns its fifth drone 0.8 s later.
  - Worst case: 0.8 + 6.0 + 804/260 = 9.9 s, before the acceleration ramp or a retreat path that does not head
    straight for the nearest edge.
  - Missing the deadline only costs a `push_warning` and a forced free (the scoring is the same as escaping), but as
    written the test's own claim is false.
  - Fix: add the ENEMIES_CLEARED section's maximum last-wave delay plus a margin. Better: add one integration case
    that runs that wave under a real `ArenaCamera` and asserts the container empties before the timeout.
- **N2: The C3 escalation threshold is a coin toss, and t15 is the worst place to find out.**
  - A rough recount from `level_1_director.gd`'s triggers, delays and formation sizes gives legacy peaks (3.5 s
    lifetime) of about 12 / 6 / 5 in the three sections.
  - At about 9 s (6 s engagement plus exit), the peaks are about 23 / 9 / 10, a ratio of about 1.9, 1.5 and 2.0.
  - The numbers are deterministic from pinned data. Compute them in the plan now and decide in advance which lever t15
    may pull without escalating. For example: REAR members disengage early, or the budget is per role.
- **N3: `SquadController` API gaps (§2.4, t4).**
  - §2.4 and §2.7 rely on a member calling `leave()` on rail suspension, but the API block has no `leave()`.
  - Deciding FLANK_LEFT versus FLANK_RIGHT needs the player's heading, but the board holds only
    `target_position_hint`.
  - "Members hold the only strong reference" is false in Assault. For loose entries, t5 writes `"squad"` into dicts
    that stay in `WaveManager._waves` for the whole section. Either keep the board only in the per-spawn copy or
    correct the claim. The unit test's WeakRef case is unaffected either way.
- **N4: The phase-offset test (§4, t8) cannot fail on its own.**
  - "5 drones hold pairwise-distinct positions after 2 s" is already guaranteed by `rear_index × TAU / n` spacing and
    by separation.
  - Tests that give every drone the same `rng_seed` also give them identical rng phases.
  - Assert R2.3 directly: with separation off and distinct seeds, the drones' corkscrew/orbit phases differ.
- **N5: The feint geometry is underspecified (§2.8, t10).**
  - A lunge at `dash_speed × 0.5` = 240 px/s that brakes at 700 px/s² stops in about 41 px. It cannot "slide past" a
    player 130 px away.
  - The plan also does not say when WINDUP starts: before or after reaching the flipped anchor. Specify the lunge
    distance or duration and the WINDUP entry condition.
  - The "> 120° bearing change" test will force a choice anyway. Better to make it here.
- **N6: Tasks that share files have no ordering.**
  - t2 and t6 both edit `enemy_mover.gd`.
  - t5, t9 and t14 all edit `wave_builder.gd`.
  - This is harmless if the runner is serial on one branch, which the CLAUDE.md "no worktrees" rule implies. If tasks
    can run concurrently, add `t6 → t2` and `t9 → t5`.
- **N7: t9's acceptance grep catches `.claude/settings.local.json`**, which an agent must not edit. Exclude `.claude/`.
  Also, level 1 has 14 drone formations (cluster ×7, wedge ×6, line ×1), not 13 as `1-context.md` says; the t1
  recount will show it.
- **N8: `StateLight`'s texture is unspecified.** If it is scene-authored inside `assault/scenes/enemies/*`,
  `test_entity_sprite_transparency.gd` sweeps it, so a solid dot PNG would fail. Use a radial `GradientTexture2D`, or
  a PNG with transparent falloff.
- **N9: The "orbit centre inside `inner_rect()`" case (§4, t10) cannot fail with the player mid-screen.**
  `_visible_rect()` is the 1480×1480 square (`arena_camera.gd:108`). Place the player within `orbit_radius` of a
  corridor edge.
- **N10: The handover bound "Δv per tick ≤ acceleration·delta + ε" (t11) is mostly guaranteed by
  `EnemyMover.step()`'s `move_toward`.** It fails only on `halt()` or `boost()`. That is fine as a guard, but it should
  not be counted as proof of a "natural" transition. Also assert facing continuity (no rotation jump beyond
  `turn_lerp`).
- **N11: The hub ring (900 ± 200 px) sits near the mission planets** at 654–742 px (`sector_hub.tscn:58, 66, 74`).
  - An idle Razor can be about 200 px from a planet, well inside `perceive_radius` 450.
  - So fights will start during the mission-trigger dwell, which cancels above 150 px/s.
  - This is already Open Question 2. Put it on the t16 playtest checklist explicitly.
- **N12: The "no `PatrolDrone` in `res://`" sweep (t16) must be limited to `.gd`/`.tscn`/`.tres`.** `docs/**/*.md`
  legitimately names it.

## Checked and fine
- Scope, the out-of-scope table and phase attribution; no build-ahead into Ph3, 4, 13, 14 or 15.
- Single-writer compliance: the `SquadController` role board, `release_constraint()` as a field write, and the brains
  requesting only.
- Signal arity (`contact_made`, `detonated`, `role_changed`).
- UID handling (`git mv` keeps the sidecars).
- Configs: flat, and `privatise()` untouched.
- Design units versus world px.
- Invariant gate floors hold: a net 0 change in roster size.
- The Bonus Drone is untouched.
- The D4 pin.
- The corridor re-pin through the rename-then-evolve split.
- Dependencies t14 → t9 and t13 → t11.
- Complexities on the other tasks are reasonable. t3 as large is defensible because it touches the `BaseEnemy` hook
  for every enemy.

---

# Plan review, round 2: Enemy rework phase 2 (Revision 2)
VERDICT: CHANGES_REQUESTED

I reviewed `3-plan.md` rev 2 and `tasks.json` against the code at HEAD `f1a7725`. I did not take the plan's numbers on
trust. I re-derived them:
- a headless script over `Level1Director._build_sections()` (in `/tmp`, nothing committed);
- a step-for-step replay of `EnemyMover.step()`'s velocity maths for both overshoot curves;
- a headless `GradientTexture2D.get_image()` probe;
- the real node positions in `sector_hub.tscn`.

Most of the revision is right:
- B1, B3, B4 and ten of the twelve N-findings are fixed.
- The C3 and deadline numbers are correct.
- The new `ContactBlast` mechanism is sound.

Two new problems block approval. Both are wrong **numbers** in fixes for round-1 findings, and each makes a task's own
acceptance criteria contradict each other:
- The Swarm's overshoot config cannot reach the ≥ 60° turn its own test demands.
- The Razor's hub anchor sits inside `perceive_radius` of a row of pickups, so the t16 clearance test fails on today's
  scene.

Each fix is a few numbers, so round 3 should be a quick confirmation.

## Round-1 findings

| Finding | Status | Evidence |
|---|---|---|
| B1 blast never lands | **Resolved** | See "ContactBlast in Godot 4.6" below |
| B2 `max_turn_rate` only turns the sprite | **Partially** | The mechanism is right: D7, `Steering.turn_toward`, a request rebuilt from `actor.velocity` every tick, and the per-tick bound, which holds because `move_toward` stays on the segment between the current and requested vectors. The **Swarm numbers are wrong**, see B5. The Razor numbers work |
| B3 Swarm hub idle unowned | **Resolved** | t8d exists, `dependsOn` [t8c, t7], config rows, and the requested tests. Swarm clearance is checked: fortuna_station (−635, 385) is 884 px from (0, 1000), and 884 − 170 = 714 > 380. Small API gaps: N15, N16 |
| B4 t8 too big | **Resolved** | Split into t8a/b/c/d. t9 → t8b, t10 → t8a, t15 → t8c and t16 → t8d are all in `tasks.json`. Acyclic |
| N1 deadline | **Resolved** | 0.8 [recomputed: cloud_descent's last wave at 76.0 s has a 0.80 s max delay] + 5.5 + 804/320 + 320/1200 + 0.5 = 9.58 s. The 804 px is correct: `_visible_rect()` 1480 plus a 64 px margin on each side = 1608. Raising the budget to 6.0 gives 10.08, so the "fails at 6.0" check works. There is also the t15 integration case. One residual in N19 |
| N2 C3 | **Resolved** | My recount matches exactly. Legacy 3.5 s: 14 / 6 / 5. At 9.1 s, all: 23 / 9 / 10; attack-capable: 19 / 8 / 7. At the real 8.3 s lifetime, capable is 16 / 7 / 7, so t15 has headroom. The levers and thresholds are decided in advance |
| N3 API gaps | **Resolved** | `leave()`, `update_target()`, and a `WeakRef` map with string keys in the spawn dicts. That fits `wave_manager.gd` (`_trigger_wave` / `_expand_formation` / `_spawn_ship` already set props before `add_child`). `Callable`s to a `RefCounted` hold an `ObjectID`, so `tree_exiting → leave` does not keep the board alive. See N14 and N15 |
| N4 phase test | **Resolved** | A same-seed control. It works because `EnemyBrain._ready()` seeds `rng` before a subclass's `_ready()` draws, as long as the subclass calls `super()` first |
| N5 feint geometry | **Resolved** | Recomputed: start at (−130, 0), lunge 162 px at 25°, then 92.6 px of braking. It ends at about 147 px from the player at a bearing of about 47° against 180°: a 133° change, above 120° |
| N6 ordering | **Resolved** | t6 → t2 and t9 → t5 are present |
| N7 grep / count | **Resolved** | `.claude/` is excluded, and there are 14 formations |
| N8 StateLight texture | **Resolved** | I verified headless that a code-built radial `GradientTexture2D` 8×8 returns an image with corner alpha 0.0, so the t8a assertion is runnable |
| N9 inner-rect case | **Resolved** | The player is placed within `orbit_radius` of a corridor edge |
| N10 Δv guard wording | **Resolved** | Facing continuity was added |
| N11 hub ring near planets | **Partially** | Fixed for the planets. Wrong for the **pickups**, see B6 |
| N12 sweep scope | **Resolved** | Limited to `.gd`, `.tscn` and `.tres` |

## ContactBlast in Godot 4.6 (B1 check)

I checked `hitbox_component.gd`, `hurtbox_component.gd`, `explosion_effect.gd`, `base_enemy.gd:153-169`,
`health_component.gd:51-53`, `score_tracker.gd:136-172` and `level_director.gd:160-205`.

**Stepping.** One main-loop iteration runs `PhysicsServer2D.flush_queries()`, then `SceneTree.physics_process` (scripts,
then the `MessageQueue` flush), then `PhysicsServer2D.step()`.
- A `call_deferred(add_child)` queued from an `area_entered` callback, or from a brain's tick, lands in that same
  iteration's message flush, before `step()`.
- The step creates the pair with the player `HurtBox`, which is monitoring with mask 1281 ∋ 256.
- The next iteration's `flush_queries` emits `area_entered`, and `HurtBox._on_area_entered` casts to `HitBox`, which
  `ContactBlast` is. The `CONTACT` damage type passes because the player's `accepted_damage_types` is empty.
- The blast's own `_physics_process` counts 1 in that iteration and 2 in the next, then calls `queue_free()`. So the
  report comes before the free even at the minimum of 2. The default of 3 gives one more step of slack, for a detonation
  from idle time or a transform update that is applied one step late.

**Lifetime and position.**
- The blast is parented to `actor.get_parent()`, which is still valid because `BaseEnemy` frees with a deferred
  `queue_free()`.
- `Health.set_health` emits on every call, and the `_detonated` flag makes repeats harmless.

**No side-effects.**
- `ScoreTracker` registers only `WaveManager.enemy_spawned` entities, so a blast is never scored as an escape.
- `_wait_enemies_cleared` counts container children, which delays it by at most 3 frames. It already tolerates pooled
  bullets in the same container.

**Test.** The new `test_contact_blast_damage.gd` asserts that player **health** actually drops, which is the
observable round 1 asked for.

---

## Blocking

### B5: The Swarm's overshoot config cannot produce the curve its own test requires (t8b; plan §2.2, §2.7 table, §2.7.1)

Checked `enemy_mover.gd:157-169`: a boost leaves `actor.velocity` at the boost vector, and a desired speed below the
current one selects `braking`.

**What happens.**
- OVERSHOOT starts at `burst_speed` 480 and requests `turn_toward(...) × max_speed` 220, so every tick is a *braking*
  tick at 500 px/s².
- Almost the whole Δv budget goes on shedding speed along the current heading. Heading only really turns once the speed
  nears 220, which takes (480 − 220) / 500 = **0.52 s of the 0.8 s window**.
- Replaying `step()` exactly (60 Hz, player 90° off the burst line at 50–400 px) gives **44°** of total turn, every
  time.
- The plan says "turns up to about 110°". The t8b acceptance criterion requires **≥ 60°**.

**Why the config test misses it.** The pinned inequality `overshoot_turn_rate × max_speed ≤ acceleration`
(528 ≤ 600) is the steady-state condition only. It ignores the deceleration phase, so it passes while the curve fails.

**What the implementer faces.** Contradictory acceptance criteria. The easy way out is to weaken the ≥ 60° assertion,
and that assertion is the one that proves B2 is fixed.

**The Razor is fine.** It starts at 480, requests 200, brakes at 700 and turns at 3.0 rad/s. It turns 90–145° before
its 20° exit or the 1.2 s cap.

**Required:**
- Pick values that satisfy the real bound and state it. Replayed results:
  - braking 900 with 0.8 s → 76°;
  - braking 1200 → 86°;
  - braking 500 with `overshoot_seconds` 1.1 → 85°. This lengthens the ram cycle to 1.95 s, which still fits
    3.5 + 1.95 ≤ 5.5.
- Replace the config pin, in both configs, with the bound that includes the braking phase:
  `overshoot_turn_rate × (overshoot_seconds − (burst_speed − max_speed) / braking) ≥ deg_to_rad(60)`. For the Razor,
  use `overshoot_max_seconds`, `dash_speed` and `overshoot_speed`: 3.0 × (1.2 − 0.4) = 2.4 rad.
- Keep the steady-state pin alongside it.
- Correct the "about 110°" sentence.

### B6: The Razor's hub anchor is within `perceive_radius` of a row of pickups (t16; plan §2.11 table and AC)

Checked `sector_hub.tscn`:
- `WeaponUnlockerSniperShot` / `Spread` / `Gatling` / `MiningLaser` sit at y = −515 (lines 187–199);
- the second `ModuleUnlocker*` row sits at y = −415 (lines 152–183).

The plan says the pickups lie at "y ≈ −212 to −315" and that the nearest to (0, −1000) is `ModuleUnlockerEmpBlast` at
740 px.

**The real numbers.**
- The nearest pickup is `WeaponUnlockerMiningLaser` (20, −515), **485 px** from the anchor.
- 485 − 200 = 285, which is **below** `perceive_radius` 450.
- A player collecting the weapon unlockers is inside an idle Razor's reach, which is exactly the ambush C4 exists to
  prevent.

**What the implementer faces.** The t16 clearance test, correctly written, fails on the unchanged scene. The t16 AC
hard-codes "Razor 540 > 450 on today's scene". The two cannot both hold.

**Required:**
- Put the Razor farther out, for example a separate `razor_ring_radius`, or `patrol_ring_radius` 1300. The (20, −515)
  pickup is then 785 px away, and 785 − 200 = 585 > 450.
- 1200 px would only just pass (485 > 450, a 35 px margin that ignores pickup and trigger radii).
- If both groups share one radius, the Swarm at (0, 1300) is still clear: fortuna_station is 1113 px away.
- Recompute the §2.11 table and the t16 AC from every direct child, including the `WeaponUnlocker*` and `LoreLog*` nodes.
- Consider adding a margin for pickup and trigger radii.

---

## Non-blocking (fix in the revision if convenient; otherwise the implementer resolves them in the named task and records the choice in DECISIONS)

- **N13: `attack_window_open` can stay open forever** (§2.4, §2.7.2; t4/t8c).
  - It is "cleared when its burst ends", but the Swarm lead's *successful* burst ends with a self-destruct on contact.
    So the burst never "ends" in the brain, and the flag stays true.
  - If the flanks trigger on the edge, they never pincer again. If they trigger on the level, they attack continuously.
  - Fix: the board records who opened the window and clears it in `leave()` / `release_lead()` for that member.
  - Add a t4 case ("the window owner freed → window closed") and a t8c case: a lead that hits the player
    → the next lead's burst opens the window again and the flanks wind up.
- **N14: `join()` semantics are unspecified** (§2.4; t4).
  - Roles are "recomputed on join". With staggered `delay()` spawns (t5), a full recompute on every join can hand LEAD to
    a newcomer or reshuffle the flanks while the current lead is mid-pass.
  - The first joins also happen before any `update_target()`, so "closest to the hint" means closest to (0, 0).
  - Specify: `join()` only fills a vacant LEAD or FLANK, otherwise it gives REAR, and never demotes. A brain calls
    `update_target()` before `join()` in `_ready()`.
- **N15: `TargetInfo` has no `heading`** (`target_info.gd`: `position`, `velocity`, `facing` only). §2.4's "as
  `TargetInfo` already gives it" and §2.7.2's `target.heading` do not exist.
  - Either add a pure `heading(min_speed := 20.0)` helper to `TargetInfo` in t4, with a unit case, or compute it in the
    brain in t8c.
  - Name the owner so t4's tests and t8c's calls agree.
- **N16: `AnchorIdle` has no home radius** (§2.5; t7).
  - "RETURNING → IDLE on reaching `anchor` within the idle ring" needs a ring size the API lacks. The Swarm idles on a
    140 px ring and the Razor on 160 ± 40.
  - Add `home_radius`: Swarm about 170, Razor 200. t7's tests should use it.
- **N17: engagement precedence for t8d** (§2.7.3).
  - "Reaches NOTICING → `set_engaged(true)`" and "beyond `lose_radius` → `set_engaged(false)`" conflict for a member
    that `force_notice()` wakes while it is beyond `lose_radius`. Possible when a member perceives at 380 px and a mate
    on the far side of a 140 px ring is at up to about 660 > 620.
  - Define one per-tick rule: `engaged = state in {NOTICING, COMBAT} and dist < lose_radius`, with `set_engaged`
    idempotent.
- **N18: `spiral()` as a pure function.** Its `radius_rate` argument only means something if the function uses it,
  for example as an added radial velocity component. The test "shrinks when negative" needs that stated. Resolve it in
  t2.
- **N19: The deadline formula ignores DISENGAGE starting mid-BURST** (§2.6).
  - `boost()` ignores requests for up to `burst_seconds` (0.45 s). The drone may then have to reverse from 480 px/s
    under `braking`.
  - The worst case is unlikely, because the nearest edge is re-chosen every tick. But the 0.5 s margin does not cover
    it analytically.
  - The t15 integration case is the arbiter. If it fails, the implementer should defer the budget's expiry until the
    boost ends and add `burst_seconds` to the formula, rather than raise the timeout.
  - B5's higher braking also helps here.
- **N20: carry-over between DURATION sections** (§5 C3; t15). `deep_space`'s last wave triggers at 29.0 s of a 30 s
  section. At 8.3 s lifetimes about 7 s of its drones overlap `asteroid_belt`, which the per-section peak does not
  count. Put "deep_space → asteroid_belt handover density" on t15's playtest checklist.

## tasks.json, holistic

- **Ownership.** Every plan section has an owning task:
  - §2.2 → t2, §2.3 → t3, §2.4 → t4, §2.4.1 → t5, §2.5 → t7, §2.6 → t6/t8b/t15;
  - §2.7 → t8b/c/d, §2.8 → t9/10/11, §2.9 → t8a/t12/t13;
  - §2.10 → t14/t15, §2.11 → t16, docs → t17.
- **Dependencies** are acyclic and complete for the file overlaps I checked:
  - `enemy_mover.gd`: t2 → t6;
  - `wave_builder.gd`: t5 → t9 → t14 → t15;
  - rosters: t8b → t9 → t14;
  - the Razor scene: t10 → t11 → t13.
- **Complexities are sensible.** t3, t8b, t8c, t10 and t15 are large. t8d, t11 and t16 are medium. t2, t7 and t8a
  are small. `tasks.json` carries no model field. That is unchanged from round 1 and not a finding.
- **Acceptance criteria are testable**, apart from the two numeric contradictions in B5 (t8b) and B6 (t16).

## Checked and fine (new in rev 2)

- `SquadController.update_target / set_engaged / is_engaged / leave`, and `AnchorIdle.hold_combat / force_notice`, are
  consistent with the single-writer rule: they are field and state writes, never motion.
- The `EngagementBudget` is gated on `EnemyWorld.arena()` (`enemy_world.gd:20`).
  `AssaultCorridorConstraint._visible_rect()` exists for `inner_rect()`.
- `release_constraint()` plus the `max_speed` write does not trip `test_enemy_mover_single_writer.gd`.
- The D7 correction to `1-context.md` is accurate (`enemy_mover.gd:182-185`).
