VERDICT: CHANGES_REQUESTED

# Review of 3-plan.md (Phase 3: Fighter, Gatling Interceptor, bullet family) and tasks.json

Reviewed against the code on `agent/auto-dev` (442dc3b). I checked the plan's claims directly. These hold up:
- The rename surface: 21 files reference `light_assault_ship`/`LightAssaultShip` or `interceptor`/`Interceptor`. That
  is level 1 ×2 and station ×4 `interceptor()` calls, plus 5 gate rosters.
- `BulletPool._exit_tree()` → `cancel_active()`, so the plan's correction of C3/S10 is right.
- `EnemyBrain.attack` is the first sibling `AttackController`, and the fighter's `AIStateMachine` is the only subject of
  `EnemyPathMover`'s name lookup.
- `WaveManager` stamps a `squad_key` on every spawn and adds `EnemyPathMover` *after* `add_child`, so the brain is
  resolved before `suspend_ai()`.
- The hub positions behind the 89 px Gatling clearance estimate are correct.
- 64 level-1 lines (16+2 / 19 / 27).
- `SquadController` already has `rear_index/rear_count/member_index`.

Overall the structure is sound: reuse of `SquadController`, `EngagementBudget`, `AnchorIdle`, `StateLight`,
`turn_toward`, a pin before migrating, and rail fallback shipped in the same task as the scene swap. Research has
tradeoffs and sources.

Five problems block approval. Four are geometry, timing or ordering specs that are internally inconsistent. An
unattended implementer will either fail their own tests or "fix" the tests. The fifth is a gate whose input data a
later task deletes. The Razor t10 notes in DECISIONS show this exact failure mode: geometry mis-specified on paper,
found live.

---

## Blocking

### B1. The fighter's pass geometry does not produce a pass at `pass_offset`. It flies nearly into the player (plan §2.4, task t8-fighter-run)

§2.4 defines two points:
- RUN_IN seeks `P + perp(h) × s × pass_offset`.
- REPOSITION's start point is `player + (perp(h) × s' − h × 0.3).normalized() × 480`.

The start point and the pass point are both offset along `perp(h)`. So the fighter approaches **laterally**, toward
the player's own side line, not parallel to `h` past it. Worked example (h = UP, s = s' = +1): start = (459.8, 137.9),
pass point = (160, 0). The line through them passes **≈ 67 px** from the player. EXTEND then "holds the heading", which
carries the fighter on toward that ≈ 67 px closest point. With a 28.6 px hull radius (`CircleShape2D` r 13 × 2.2 in
`light_assault_ship.tscn`), that is a near-ram.

This contradicts:
- §4's own `test_fighter.gd` case: "closest approach … within `pass_offset ± 40` px on side `s`";
- the cited source. Research finding 3 (Reynolds) offsets perpendicular to the **pursuer's line of approach**, not to
  the target's heading.

The same issue drives the Assault case: "passes are lateral" is only true because the approach is aimed at the player.

**Required:** re-specify the pass using one of these:
- (a) Reynolds offset: perpendicular to the fighter→`P` line, with a look-through point beyond `P` so RUN_IN does not
  stall at the seek target;
- (b) a start point along ±`h` so the run is parallel to `h`.

State which "side" `s` means (the side of approach or the side of the pass), since the pincer and the solo alternation
both depend on it. Check the result numerically in the plan: the closest approach must equal `pass_offset`.

### B2. Gatling convergence is mis-sequenced, and its own test cannot pass (plan §2.6, §2.6.1, tasks t10-gatling-windows / t11-gatling-convergence)

The plan's timings:
- The LEAD's light goes CHARGING at **SWING_IN** entry (§2.6, 0.5–1.5 s before SPIN_UP).
- The LEAD opens the window and writes `convergence_point` only at **SPIN_UP** entry.
- The FLANK answers the window by *starting* its own SWING_IN (up to `swing_in_max` 1.5 s) and then SPIN_UP (0.25 s).
- The LEAD streams 0.25 s after the window opens, for 0.72–1.08 s. Its COOLDOWN then closes the window, and §2.6.1
  resets the FLANK's `aim_point` to INF at that moment.

As specified:
- the two lights are **not** CHARGING "within one tick" (t11's first acceptance line). They are 0.5–1.5 s apart;
- the FLANK often reaches STREAM after the LEAD's window has closed, so it fires with no `aim_point`. Convergence
  fire (R3.10) then silently never happens, and "aim lines within 48 px of the point" either fails or is only
  satisfiable in a staged test.

**Required:** synchronise the pair. For example:
- the LEAD opens the window at its SWING_IN entry;
- both brains hold in SPIN_UP until both are in position, or until a bounded wait expires;
- the window closes on the **later** of the two COOLDOWNs;
- the point is refreshed or held for the stream's duration.

Then make the test assert overlapping STREAM intervals, not only CHARGING.

### B3. The Assault Gatling's side rule contradicts the REPOSITION flip (plan §2.6, task t10)

Two rules conflict:
- In Assault, `side` = "the half of `inner_rect()` opposite the player's x", and a t10 test asserts the Gatling sits
  there.
- REPOSITION always sets `side = −side` "then … swing to the new `F`".

Either the flip is a no-op in Assault (and R3.7's "attacks from the other side" is lost there), or the second window
is on the player's own half (and the t10 test fails). **Required:** say which rule wins in Assault, and in which
phase the "opposite half" assertion applies.

### B4. The cloud_descent deadline arithmetic is wrong, and the formula is missing a term (plan §2.9.3, task t17-level1-cloud)

- `WaveManager._process` emits `waves_complete` **at the moment the last wave triggers** (76.0 s), not "≈ 76.8 s".
  The delayed spawns are `create_timer` awaits after that. So the ENEMIES_CLEARED clock ends at 76.0 + 10 = **86.0**.
- The boundary row "fighter moved into the 76 s wave fails (76.8 + 9.5 > 86.8)" is false as written: 86.3 < 86.8.
  With the correct 86.0 it fails only when the moved fighter has delay ≥ 0.5 s. With delay 0 it gives 85.5 and
  *passes*. The boundary must name its delay, or it proves nothing.
- §2.4 says "DISENGAGE waits for `BurstClock` to finish" (and the telegraph?), and §2.6 says the same for STREAM. The
  Razor precedent put its dash deferral into the formula. The per-entry fighter formula must add the worst deferral:
  telegraph 0.3 + the longest burst (7 × 0.05 or 5 × 0.10 s).
- The Gatling boundary row needs the same deferral term: 12 × 0.09 s stream plus spin-up.

The resulting margin (≈ 82.3 + 0.7 vs 86.0) is fine. The spec just has to be right, because the test is the gate.

### B5. t2-rounds cannot meet its own acceptance criteria, and it collides with t6/t7 (tasks.json t2-rounds, t6, t7, t8)

t2 must "read speeds from `FighterConfig` / `GatlingInterceptorConfig` fields, not by regex". Neither exists at t2:
- `FighterConfig` (`fighter_config.gd`) has no bullet-speed fields. 420/250 are literals in
  `light_assault_ship.gd:42`, and only t8 adds config fields.
- `GatlingInterceptorConfig` is created in t7.

t2 depends on nothing, yet t2, t6 and t7 all edit `tests/integration/test_enemy_bullet_lifetime.gd`:
- t6 must repoint the regex path;
- t7 renames `InterceptorConfig`, which that file reads.

The sweep must also include the **rail-fallback speeds** (§2.8: Pulse at 250 and 420, Gatling Stream at 220). Those
are below the Pulse scene's 300, and the check is written against `scene_speed`.

**Required:** either
- make t2 depend on t7 and have t8/t10 extend the sweep with the new config fields, **or**
- keep the regex/InterceptorConfig reads in t2 and move "read from configs" into t8's and t10's acceptance criteria.

In both cases the rail speeds must be config fields that the sweep reads.

### B6. The legacy density baselines are computed from data that t16 deletes (plan §2.9.1–2.9.2, tasks t1-pin / t16)

t1 computes the legacy peak fighters and peak shots/s "from each entry's legacy lifetime (`free_after`, or the rail's
on-screen time from its movement and speed)". t16 then **strips `.move()` and `.free_after()`**, which are exactly
those inputs. The pinned rows keep only "whether movement is set", not speed or shape.

After t16, the 1.5× / 2.0× / 1.25× gates have no legacy value to divide by, unless the test hand-types one. The plan
says it will not do that. (Ph2 got away with this because the drone legacy lifetime was a single constant,
`_LEGACY_LIFETIME = 3.5` in `test_level1_drone_spawns.gd`.)

**Required:** t1 freezes the per-section legacy peak fighters and peak shots/s as a pinned constant table (the Ph2
`_EXPECTED_LEGACY_PEAKS` shape), computed once from the live rails and asserted equal while the rails exist. t16 keeps
dividing by those constants.

---

## Should fix (with the above; not blocking on their own)

1. **Pool sizing ignores the rail cadence** (§2.2, §2.8, t8, t10).
   - The Fighter rail FORWARD fallback fires Pulse every 0.3 s at 420 px/s from the 10-round `AimedPool`. That is
     1400 / 420 ≈ 3.3 s of life, so ~12 rounds in flight. The legacy pool was 20 (`light_assault_ship.gd`).
   - `pool_size_for` is asserted only for AI bursts. The station's TOP rail fighters (`shoot_forward`) can starve,
     silently (`acquire()` → null plus a warning), and the t1 rail-fire test (≥ 1 shot) will not notice.
   - Assert `pool_size ≥ pool_size_for(...)` for the rail cadence too, or size the pool to the max of the two.

2. **The "bit-identical" claims are false** (§2.0 X7, §2.3, t3).
   - `vel.angle() − PI/2` and `atan2(−vel.x, vel.y)` differ by **2π** for headings in the upper-left quadrant, e.g.
     vel = (−1, −1): −5π/4 vs 3π/4.
   - `Vector2.RIGHT.rotated(r + PI/2)` equals `Vector2.DOWN.rotated(r)` only within float epsilon.
   - The t3 tests "bit-identical" and "legacy equality over 8 headings" should use `angle_difference` or
     `assert_almost_eq`, as `test_enemy_path_mover.gd::test_facing_matches_the_nose_down_convention` already does.
   - Also reuse `EnemyMover._sprite_forward_angle()`'s duck-typed read (`enemy_mover.gd:235`, with
     `DEFAULT_SPRITE_FORWARD_ANGLE`) through one shared static helper, instead of a third copy in the patterns and
     `EnemyPathMover`.

3. **Where the pools sit in `fighter.tscn`** (§2.4: "`AimedAttack` … with pool `AimedPool`").
   - `BulletPool._ready()` resolves its container as `get_parent().get_parent()`. A pool authored as a child of the
     `AttackController` node would reparent live bullets under the **ship**, so they would move with it.
   - State that both pools and the Gatling pool are direct children of the root.

4. **Art tasks miss `_rotate_sprite`** (t14-art-fighter, t15-art-gatling).
   - `BaseEnemy._rotate_sprite()` flips any child named `AnimatedSprite2D` by 180°.
   - The fighter's `HitFlashAnimationPlayer` tracks `AnimatedSprite2D:material`.
   - `test_base_enemy.gd:304,318` hard-codes `light_assault_ship` in the flip list, and asserts every other enemy has
     no `AnimatedSprite2D`.
   - `sprite_forward_angle` must be derived *after* that flip. The art task must name the node type, and it must
     update the animation track and test list if the type changes.

5. **The fighter attack window has no close rule** (§2.5, t9).
   - FLANKs "answer each window once" (`_answered_window`). That resets only when the window reads closed
     (`swarm_drone_brain.gd:201-202`), and the Swarm LEAD closes it explicitly (`:494`).
   - §2.5 says when the fighter LEAD opens the window, not when it closes it. Specify the close point, e.g. on EXTEND
     entry.

6. **Role side vs. the "no cross-over" test** (§2.5, t9).
   - `SquadController._side_for()` hands the second flank candidate the *other* flank role when both are on the same
     side of the player. A FLANK_LEFT can therefore sit on the right.
   - If `s` comes from the role (FLANK_L = −1), that member must cross, and the "no member crosses sides" test fails.
   - Define the rule: take `s` from the current position for the pass in progress, or allow a crossing only through
     REPOSITION. Assert that rule, not an absolute.

7. **The requirement wording in §1 is overstated** (§1, §6 R3.4).
   - §1 promises "three fighters … as a pincer, while a fourth comes head-on".
   - §2.5 delivers LEAD (frontal) + 2 FLANKs + a dry REAR, because the attacker cap is 3 (research finding 1).
   - That is a defensible reading of IDEAS §5.3, but state it as a deviation in §2.0 and DECISIONS, and fix §1.

8. **t5 needs a W layout class** (task t5-w-formation).
   - Every existing helper returns a `FormationResource` subclass in `global/resources/formation/`, e.g.
     `VFormation.compute_slots()` with stagger delays.
   - `w_formation()` needs a `WFormation` class there. Name it in t5, and decide the stagger. The research proposed
     `stagger`; the plan dropped it.

9. **Task sizing** (t8-fighter-run).
   - t8 bundles: the scene rebuild, the config, the brain's six phases, two weapons with hysteresis, the rail fallback,
     deleting `states/`, and dual-harness specs.
   - Ph2 split the equivalent Swarm work into t8b/t8c/t8d, and the one-task Razor (t10) produced the largest set of
     deviations.
   - Consider splitting t8 into two tasks:
     - (a) scene, config, rail fallback and a minimal brain with DISENGAGE (behaviour-neutral on rails, which is what
       t1 guards);
     - (b) the attack-run flight and weapon selection.
   - Not blocking if you keep it, but B1 lands in this task.

10. **Minor:** t7 is marked `small` but touches ~12 files, including `station_reinforcements.gd`, `level_1_director.gd`,
    five gate files and `test_enemy_bullet_lifetime.gd`. It should be `medium`, like t6. `tasks.json` has no model
    assignments, so there are none to check.

---

## Checked and fine

- Dependency chain: t6→t7→t8→t10→t11→t12→t13. t16 comes after t9/t11. t18 comes last.
- t12's `start_engaged` seam only affects Open Space tests. The Assault tests in t16/t17 are unaffected, because idle
  is skipped there.
- The Heavy Shell ships unused, but it is tested with a fixture and its future consumer is recorded (S5).
- No UID is hand-typed: `git mv` keeps the sidecars, and the acceptance criteria include the UID and load-integrity
  gates.
- The single-writer gate is respected: all motion goes through `EnemyMover` plus `turn_toward`, as the Ph2 decision
  that "a curved path is a brain-side request" requires.
- Signal arity: `weapon_mode_changed(mode: int)` and `phase_changed(new_phase: int)`.
- Design units are preserved in level edits: only `.move()`, `.free_after()` and `shoot_*` are stripped.
- Scope boundaries against Ph4, Ph5, Ph13, Ph14, Ph15 and Ph17 are respected and listed in §6/§7.

---

# Round 2 review (revision 2, commit 3738613)

VERDICT: APPROVED

I checked revision 2 against the code on `agent/auto-dev` (3738613), not against §9's own account of it. All six blockers
are genuinely fixed, and I redid the numbers myself (below). No new problem is severe enough to block. The revision
did introduce a few inconsistencies an unattended implementer would hit, though, so the notes N1–N6 below are
**required reading for the named tasks**. Each one says which way to resolve it, so no task has to stall or
re-litigate. N7–N12 are minor.

## Round-1 findings

| # | Status | Evidence |
|---|---|---|
| B1 pass geometry | **Resolved** | Recomputed §2.4.1 (3-plan.md:222-258) with `P̂=(0,0)`, `h=UP`, `left(v)=v.rotated(−PI/2)`. FLANK_LEFT: `b=(−1,0)`, `S=(−480,−160)`, line `y=−160`, closest approach **160**. FLANK_RIGHT: `S=(480,−260)`, **260**. FRONTAL σ=+1: `S=(160,−480)`, line `x=160`, **160**. `|S−P̂|=506 < fire_range 520`. RUN_IN seeks projection + `lookahead·u`, so the target is always 220 px ahead and it cannot stall. It ends on `(P̂−X)·u<0`. For a player holding course, the closest approach equals `|l|` by construction. See N1 for the moving-player case |
| B2 convergence sequencing | **Resolved** | 3-plan.md:460-510. The window opens at the LEAD's SWING_IN (the same tick as CHARGING), and the FLANK answers ≤1 tick later, so "CHARGING within one tick" is satisfiable. SPIN_UP rendezvous: STREAM when all stages ≥1, or `sync_wait_max`. The point is refreshed every tick, and the window closes when every stage is 2 (the later COOLDOWN). Overlap check: 8 rounds × 0.09 s = 0.72 s of STREAM, starts within one tick (0.0167 s), so overlap ≥ 0.70 s ≥ 0.6. That holds even on first-to-last shot (0.63 − 0.017 = 0.61). LEAD-before-FLANK-key race: the LEAD's own 0.25 s spin-up covers the FLANK's one-tick answer delay. See N3 |
| B3 Assault side rule | **Resolved** | 3-plan.md:418-427. "First window opposite; every later window flips; skip the flip if the clamped flipped `F` is < 220 px from the player." Checked the wall case against `AssaultCorridorConstraint.inner_rect()` (= the 1480×1480 visible rect, `arena_camera.gd:108`): a player 100 px from the right wall gives a flipped `F` ≤ 100 px away, which is < 220, so it stays left. Consistent with the t10 test. See N7 for the centre tie |
| B4 deadline arithmetic | **Resolved** | `wave_manager.gd:56-64` emits `waves_complete` in the same `_process` tick as the last `_trigger_wave`. Delays are `create_timer` awaits (`:170-173`), and `level_director.gd:159-168` starts the timeout at that emit. `level_1_director.gd` cloud_descent: the last fighter wave is 72.0 s, and its latest entries are the two `.delay(0.8)` lines (72.8). The 76.0 s wave is drones only, max delay 0.8. Recomputed: worst entry (72.8−76.0)+6.0+0.8+2.84+0.5 = **6.94 < 10**. Boundary at delay 0.8: **10.94**. Gatling: 7.0+2.08+1.30+(804+37.6)/520+0.5 = **12.5**. `worst_exit` 1.17+1.67 = 2.84 matches the Razor shape in `test_engagement_deadline.gd:91-95`, and 804 matches `:164`. The deferral terms are present (fighter 0.8, Gatling 2.08). The SWING_IN budget-entry rule is what makes 2.08 a true bound. See N5 |
| B5 t2 sources / collisions | **Resolved** | t2 keeps today's sources (`test_enemy_bullet_lifetime.gd:62` `InterceptorConfig`, `:74-83` regex). t6 and t7 depend on t2 and only repoint. t8a and t10 switch to config fields, with the rail speeds now config fields (`rail_aimed_speed`, `rail_forward_speed`, `rail_stream_speed`), and both tasks' acceptance criteria say so. Per-round check against the slowest fired speed: Pulse 1400/250 = 5.6 ≤ 8, Scatter 450/420 = 1.07 ≤ 2, Gatling 1400/220 = 6.36 ≤ 8, Heavy 1800/160 = 11.25 ≤ 12. All pass |
| B6 frozen baselines | **Resolved** | 3-plan.md:574-594 and t1. `_LEGACY_PEAK_FIGHTERS` / `_LEGACY_PEAK_SHOTS_PER_S` are frozen from the first computed run and asserted equal to the live computation while the rails exist. The equality is retired per migrated section, and the gates divide by the constants. See N6 on one input |
| SF1 rail pool sizing | Resolved | Max(AI, rail) with both asserted. The rail Gatling exception is named. See N4 |
| SF2 angular equivalence / one helper | Resolved in intent. **See N2**: the "only reader" sweep will find two readers the plan does not mention |
| SF3 pool placement | Resolved | Root children, with a scene assertion; matches `BulletPool` grandparent resolution |
| SF4 `_rotate_sprite` | Resolved | Keeping the node type and name is the least-churn answer, and `sprite_forward_angle` is defined after the flip |
| SF5 fighter window close | Resolved | Closes on the LEAD's EXTEND entry. `_reassign()` already closes it on a LEAD change (`squad_controller.gd:216-217`) |
| SF6 side vs cross-over | Resolved | Latched pass plus the REPOSITION-only rule, asserted as a rule, not an absolute side. This matches `_side_for` (`squad_controller.gd:252-259`) |
| SF7 §1 wording | Resolved in the plan and in DECISIONS. The tasks.json t9 title still says "a fourth comes head-on" (N11) |
| SF8 WFormation | Resolved | Class, stagger and the W5 numbers check out: x = −120…120; delays 0.2/0.1/0/0.1/0.2 |
| SF9 t8 split | Resolved | t8a (medium, rail-neutral shell) and t8b (large) |
| SF10 t7 sizing | Resolved | Now `medium` |

## Notes an implementer must apply (not blocking; each has a stated resolution)

**N1 — t8b: measure the closest approach to `P̂`, not to the live player, in the moving-player case.**
(3-plan.md:232 and :786; tasks.json `t8b-fighter-run` acceptance, "for a holding and a moving player")
- The pass line is anchored on `P̂`, and `P̂` leads the player by 0.3–0.8 s.
- With the player at 200 px/s along `h`, a FLANK lane (`l ∥ h`) therefore sits 60–160 px further ahead of the **live**
  player. The closest approach to `P` is then ≈ 220–320 px, which can never satisfy `pass_offset ± 40`.
- FRONTAL is unaffected, because its lane is ⟂ `h`.
- **Resolution:** in the moving case, assert the closest approach against the tick's `P̂` (the lane's own anchor).
  Keep the live-`P` assertions for the stationary case and for the "ahead" side check (`(X − P)·h > 0`). Do **not**
  change the geometry to anchor on `P` to make the test pass.

**N2 — t3: the "only reader" source sweep will fail unless t3 also migrates two existing readers.**
- `assault/scenes/enemies/swarm_drone/swarm_drone_brain.gd:689` and `razor_drone/razor_drone_brain.gd:771` each have
  their own `actor.get(&"sprite_forward_angle")` inside `_facing()`.
- Neither the plan nor the task mentions them, so the t3 acceptance line ("finds no other
  `get(&"sprite_forward_angle")` reader") fails on the first run.
- **Resolution:** t3 rewrites both `_facing()` bodies as
  `Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))`, which is behaviour-identical
  within epsilon.
- Scope the sweep to non-test `.gd` files. `tests/unit/test_enemy_mover.gd:213` legitimately calls it.
- The existing Swarm and Razor tests must stay green.

**N3 — t11: the FLANK must take the LEAD's *intended* side, not the LEAD's current position.**
(3-plan.md:474-477)
- From the second window on, REPOSITION has flipped the LEAD's `side`. The LEAD opens the window at SWING_IN entry,
  after only 1.0–1.5 s of swinging at ≤ 260 px/s, so the ≈ 760 px crossing is often unfinished.
- The cross-product of the LEAD's *position* then names the **old** side, and the FLANK goes to the opposite flank.
  That is exactly the both-sides crossfire that finding 5 forbids.
- The t11 cases only exercise the first window, so this would ship silently.
- **Resolution:** read the LEAD's `side` (or its current flank point `F`) duck-typed through `members()`/`role_of()`.
  No new SquadController API is needed.
- Add a **second-window** same-half-plane case to `test_gatling_convergence.gd`.
- Also state which FLANK phases may answer. Recommended: only APPROACH, COOLDOWN or REPOSITION. A FLANK mid-SWING_IN,
  SPIN_UP or STREAM of its own window skips, as a far FLANK does. Never abort a live stream.
- Apply the same rule to fighter FLANKs in t9 (3-plan.md:348): a FLANK answers only once it is loitering at `S`. A
  FLANK still in APPROACH does not answer; it attacks via `flank_wait_max` after arriving. Entering RUN_IN from
  mid-approach on the wrong side of the player would satisfy `(P̂−X)·u<0` on its first tick.

**N4 — t8a: the fighter's minimum burst period has two values in the plan.**
- §2.2 (3-plan.md:134) sizes the Pulse pool with a 2.5 s AI period, giving 10. §2.9.2 (:616) counts shots/s with a
  "minimum burst period ≈ 1.2 s".
- No config field or brain rule enforces either value. The only rule is "at most one burst per pass leg", and legs can
  be short (the solo TURN below). So `pool_size_for(…)` in the t8a test takes whatever constant the implementer types,
  and the test is tautological.
- At 1.2 s the Pulse AI need is 5 × ceil(4.67 / 1.2) = **20**, not 10. The pool of 12 would then starve silently (K4).
- **Resolution:**
  - add a flat `min_burst_period` field to `FighterConfig` (1.2 s);
  - have the brain enforce it between any two bursts;
  - use it in both the pool assertion and the t16 shots/s numerator;
  - size `AimedPool` to `max(AI, rail)` from it (20 at 1.2 s).

**N5 — t17: the fighter deadline boundary row does not survive pre-approved lever 1.**
- The row "fighter in the 76.0 s wave at delay 0.8 computes 10.94 and fails" assumes `engage_seconds` 6.0.
- Lever 1 (6.0 → 4.5) is pre-approved and is named in K2 as the cloud_descent mitigation. It gives
  0.8 + 4.5 + 0.8 + 2.84 + 0.5 = **9.44 < 10**, so the boundary assertion itself goes red.
- **Resolution:** derive the boundary from config rather than a fixed delay. Place a synthetic fighter entry at relative
  time `timeout − (engage + deferral + worst_exit + MARGIN) + 0.25`, and assert that the function rejects it.
- Keep a second, literal row that asserts the *shipped* 76.0 s wave contains no fighter.
- Record in DECISIONS which lever, if any, was used.

**N6 — t1: the legacy interceptor's shots/s contradicts the plan's own §2.2.**
- §2.9.1 (3-plan.md:588) credits each legacy interceptor with 1/0.09 ≈ 11.1 shots/s.
- §2.2 states that the legacy pool of 20 against a 6.36 s round life made it fire about 20 rounds and then stall. Its
  steady-state throughput is ≈ 20 / 6.36 ≈ 3.1 shots/s.
- deep_space's frozen baseline is therefore inflated by up to ≈ 16 shots/s, and its 1.25× gate is correspondingly
  loose. The §4 boundary "a 3rd Gatling pushes shots/s over" may then not trip at all. By my rough estimate it is
  marginal.
- **Resolution:**
  - compute a legacy shooter's rate as `min(1 / fire_interval, pool_size / round_lifetime)`, from the live legacy scene
    before t7/t10 change it;
  - replace the hand-verified 3rd-Gatling boundary with a computed mutation that is asserted to fail;
  - if no single added enemy trips it, state the actual headroom in DECISIONS instead.

## Minor (fix in passing)

**N7 — t10: the Assault "player at the corridor centre" test is a tie** (3-plan.md:788). "Opposite the player's x" is
undefined at exact centre. Place the player off-centre (e.g. 150 px left), or define the tie-break (`0 → +1`, as the
Open Space rule does).

**N8 — t8b: solo / same-kind repeat passes make TURN degenerate.**
- The problem cases:
  - For a solo fighter, FLANK_LEFT → FLANK_RIGHT, the next `S` lies *ahead* on the extension line. With the plan's
    numbers, EXTEND ends near x ≈ 311 on `y = −160`, and the next `S` is at (480, −160). TURN ends on its first tick
    (heading already within 20°).
  - For a repeated FLANK_LEFT, the fighter reaches `S` heading ≈ 160° off `u`.
- In both cases REPOSITION's "within 80 px of `S` with heading within 30° of `u`" is reached only by the 3.0 s
  `reposition_max` fallback, after a seek-overshoot loop.
- It does progress, but the "visible wide turn" then happens in REPOSITION, and opportunity (b) never fires for a
  solo fighter.
- **Resolution:**
  - REPOSITION seeks an entry point `S − u·lookahead` before handing over to RUN_IN's path following. The arrival
    heading then comes out right without a loop;
  - measure the "TURN radius within 15 %" case on a pass that actually turns (a FRONTAL alternation or a repeated
    flank), not on a degenerate one.

**N9 — t8b: FRONTAL fallback lane.** When APPROACH breaches `standoff_radius` and re-bases as FRONTAL with `b` from
the current bearing (3-plan.md:275), the lane must be `right(u)·σ·pass_offset` (⟂ the new `u`), not `right(h)·…`.
Otherwise the closest approach is not `|l|`.

**N10 — t11: "aim lines within 48 px"** should mean the pre-jitter direction (the shooter → `aim_point` line after the
±3° window error). Including the ±0.05 rad per-round jitter gives ≈ 5.9° total, which is ≈ 48 px at 470 px range and
therefore flaky.

**N11 — tasks.json `t9-fighter-squad` title** still reads "a fourth comes head-on", which contradicts X9. Use "two
fighters close as a pincer while the leader comes head-on".

**N12 — file overlap without an ordering edge.** `t12-shooter-idle` and `t14-art-fighter` both edit
`tests/integration/test_fighter.gd` and the fighter scene. `t12` and `t15-art-gatling` do the same for the Gatling,
and none of these pairs has a dependency edge. This is harmless if the board runs tasks serially. If it can run them in
parallel, add `t14 → t12` and `t15 → t12`.

## Checked and fine this round

- DECISIONS.md (the plan commit's diff) matches revision 2: the X6 fields, the one helper, the per-entry formula with
  deferral, the X9 deviation, frozen baselines, the Gatling side rule and the SWING_IN budget rule.
- Dependencies in tasks.json match plan §3 exactly: t6←{t1,t2}; t7←{t1,t6}; t8a←{t2,t3,t6}; t8b←t8a; t9←{t8b,t4,t5};
  t10←{t2,t3,t4,t7,t8b}; t11←t10; t12←{t9,t11}; t13←t12; t14←t9; t15←t11; t16←{t1,t9,t11}; t17←t16; t18←all
  leaves. There are no cycles, and the chain does not stall.
- Complexity: t8a `medium` and t8b `large` are right. t11 `medium` is acceptable, since t4 already owns the fields.
- `SquadController.leave()` + `_reassign()` (`squad_controller.gd:59-71, 189-217`) will clear the X6 fields on both
  LEAD-leave and closer-join paths. t4's cases match.
- `GatlingAttackPattern` (`gatling_attack_pattern.gd`) has no `rng`/`aim_point` today, and `aim_point` bypasses
  `accuracy`, so the convergence aim error is only the stated ±3° + jitter.
- The Assault world is the 1480 × 1480 visible rect (`arena_camera.gd:108-111`), so `standoff_radius` 480, TURN
  diameter ≈ 333 and `preferred_range` 380 all fit. The `min_run_length` / lane-flip clamps only matter near walls,
  which is what their boundary cases test.
- Scope is unchanged from round 1. Nothing from Ph4/5/13/14/15/17 has crept in, and every deferral is listed in §6/§7
  with a reason.
