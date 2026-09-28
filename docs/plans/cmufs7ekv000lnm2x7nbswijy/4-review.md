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
