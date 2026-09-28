VERDICT: CHANGES_REQUESTED

# Round 1 — review of `3-plan.md` (t10-brain-mover)

Checked against `agent/auto-dev` @ `4bb244a`. I read the epic plan (§2.2–§2.4, §2.10, P-9, P-10), its review
(F3, F11, N2, N7), CLAUDE.md, tests/README.md, and the code itself: `base_enemy.gd`, `enemy_path_mover.gd`,
every `BaseEnemy` subclass, `global/enemy_ai/*.gd`, `attack_controller.gd`, `wave_manager.gd:176-208`,
`test_enemy_path_mover.gd`, `test_ship_rotation_single_writer.gd`, `test_project_load_integrity.gd`,
`test_drone_interceptor.gd` / `test_patrol_drone.gd` (harness notes), `addons/gut/error_tracker.gd`, and
`tests/helpers/`. I checked the float-timing claims by running a script in the headless Godot 4.6.3 binary.

The architecture is right, and it is faithful to the approved epic:
- The tick is owned by `BaseEnemy`. Brain and mover are resolved by type.
- The path mover's name lookup stays unconditional (F3). `halt()` routes the zeroing through the mover (N2).
- `global/` code is typed `CharacterBody2D`, and `sprite_forward_angle` is read duck-typed (F11).
- The plan reuses `Steering` and `EnemyWorld` and reinvents nothing.
- Every requirement in the task description is covered.

The changes requested below are in the mover's `arrive` wiring and in the test plan. As written, several of
the plan's stated expected values are wrong, and a few of its tests cannot fail in the way that matters. An
unattended implementer would hit red tests with no guidance, and would either fudge them or ship gaps.

## Required

### R1. The `arrive` / `hold_position` wrappers pass the wrong deceleration. `3-plan.md:71-74`, `global/enemy_ai/steering.gd:20-35`
In the plan, `arrive(target, speed)` passes the mover's `acceleration` to `Steering.arrive`, and so does
`hold_position`. But `Steering.arrive` uses that argument to compute the slowing radius, `v²/(2·accel)`. The
steering doc says the radius must match the ship's actual deceleration: "a too-short radius overshoots and
oscillates". In `step()` the ship actually decelerates at `braking`, whenever `braking > 0` (plan line 86).

Two cases go wrong:
- **`braking < acceleration`** (for example 300 against 600): the radius is half the stopping distance, so
  the ship overshoots and oscillates.
- **`acceleration = 0, braking > 0`**: arrive gets 0, so there is no ramp. The ship runs at full speed into
  the target, then brakes past it.

**Fix:** both wrappers pass the effective deceleration, `braking if braking > 0 else acceleration`.

### R2. The mover's steering wrappers have no tests. `3-plan.md:194-218`
The unit-test list covers `request_velocity`, the limits, facing, boost and halt. None of the nine wrappers
is tested: seek, arrive, orbit, intercept, retreat_from, evade, strafe, hold_position, drift.

They are one-liners, but they are exactly where argument order breaks. `arrive` and `hold_position` each
take six positional arguments, `vel` and `accel` among them, and `orbit` takes five.

**Fix:** add one case per wrapper, stepped once with all limits at 0 and the actor at a known position.
Each case asserts `actor.velocity == Steering.<x>(<the same args>)`. Assert on `velocity`, not position,
because the manual `move_and_slide` delta is unreliable (see N1). Add an arrive case with
`braking ≠ acceleration` that pins R1.

### R3. The plan's float-timing expectations are wrong, verified on the real engine. `3-plan.md:215`, `:231-233`
This is the same trap as the epic review's N7. I ran it in `godot --headless` (4.6.3) with `dt = 1.0/60.0`:
- **`boost(RIGHT, 480, 0.1)` does not end on step 7.** After 6 steps of `timer -= dt`, the timer is a tiny
  positive number (the `t > 0.0` check still returns `true`), so a `> 0` check boosts on step 7 as well.
  The plan says "480 for 6 steps, ends on the 7th".
- **`decision_interval = 0.25` gives 7 decisions in 120 frames, not 8.** Fifteen frames accumulate to just
  under 0.25 (`b >= 0.25` returns `false`), so the first draw lands on frame 16. The last one due at 2.0 s
  lands just past frame 120.
- Checked and fine: `acceleration = 600`, 30 steps of `move_toward` gives exactly `(300, 0)`.

**Fix, either one:**
- use a dyadic step in these cases (for example `dt = 1.0/64.0`, `0.125`, `0.0625`), so the sums are exact;
- or state the expected counts as the engine actually produces them, with the boundary expressed as a window.

Pick one and write the numbers in the plan, so the implementer does not re-derive or loosen them.

### R4. The single-writer sweep misses component writes and the rotation helpers. `3-plan.md:163-171`
**Component writes.** The regexes require `velocity` / `rotation` to be followed directly by an assignment
operator. So `velocity.x = …` / `actor.velocity.y += …` never matches. This is a live idiom in this codebase:
`gunship.gd:95,101,103,105` write `velocity.x` / `velocity.y`. A future mover-driven root or brain that
copies the gunship would get past a gate whose job is to catch exactly that.

**Rotation helpers.** `actor.look_at(…)` and `actor.rotate(…)` write `rotation` too, and bypass the one
facing rule. They are the most natural thing for a brain author to reach for.

**Fix:**
- Allow an optional `(\.[xy])?` after `velocity` in both roster A and roster B.
- Add `look_at(` / `rotate(` to both rosters: through a receiver in A, bare or `self.` in B.
- Extend the boundary list to cover the new patterns: `"velocity.x = 0.0"` (B) and `"actor.look_at(p)"` (A)
  are reported, and `"var s := velocity.x"` is not.

### R5. The "no brain → inert" case cannot see the likely regression. `3-plan.md:234-236`
The likely regression is that `BaseEnemy._physics_process` steps the mover even when there is no brain. The
fixture keeps its `EnemyMover` with the brain removed, and starts at zero velocity. A stepped mover with no
request writes `velocity = 0` and calls `move_and_slide()` with zero velocity. That is indistinguishable
from inert.

**Fix:** set a non-zero `velocity` (for example `(50, 0)`) before calling `_physics_process(dt)`, and assert
that `velocity` is unchanged, as well as position. `free()` the removed `Brain` node, or GUT reports an
orphan.

## Non-blocking (apply while implementing)

- **N1. Factual error about `move_and_slide()`.** `3-plan.md:248-249` says that outside a physics frame it
  "uses the physics step as delta". It does not. The engine uses `get_process_delta_time()` when
  `Engine.is_in_physics_frame()` is false, and this project's own harness notes
  (`test_drone_interceptor.gd:13-27`, `test_patrol_drone.gd:19-25`) record that the resulting motion
  varies from run to run.
  - The plan's mitigation stands: assert on `velocity`, and on position only as moved / not moved.
  - Correct the sentence.
  - Give the script-built test actor `motion_mode = MOTION_MODE_FLOATING` (a bare `CharacterBody2D.new()`
    is GROUNDED), so floor logic can never touch `velocity`.
- **N2. Sniper is filed in the wrong list.** `3-plan.md:127` and `1-context.md` list `sniper_enemy` among
  the subclasses that override `_physics_process`. It does not: `sniper_enemy.gd:51` is `_process`, on
  purpose (see its header). After t10 it *inherits* `BaseEnemy._physics_process` and is inert, like LAS,
  interceptor, bonus drone and station. There is no behaviour change. Fix the list so docs and
  DECISIONS.md do not carry the error.
- **N3. Direct calls and engine ticks can overlap.** The fixture is a `BaseEnemy` with `_physics_process`,
  so the engine enables physics on it at READY. Tests that call `_physics_process(dt)` by hand must either
  run without an `await` in between, or `set_physics_process(false)` first, as t2's harness note 2 does.
  They must **not** do that in the path-mover case: there, `is_physics_processing() == false` is the
  assertion, and disabling it by hand would make that assertion vacuous.
- **N4. Make the real-frames tick count exact.** Assert `tick_count == frames waited` (±1) rather than
  "advances". Also assert that `EnemyBrain` and `EnemyMover` are not physics-processing themselves. A
  brain that also ticks itself would double-count, and "advances" would still pass.
- **N5. How roster B finds the root script.** Plan line 168 does not say how the root script is resolved.
  Read it through `PackedScene.get_state()`: node 0's `script` property, the same approach the
  sprite-transparency gate uses. Then walk `get_base_script()`, which correctly returns null past
  `base_enemy.gd`, since its base is native. Match the `.tscn` text on the full
  `res://global/enemy_ai/enemy_mover.gd` path, not the bare file name.
- **N6. Do not copy uid lines from the template.** When hand-writing `fixture_enemy.tscn` from
  `drone_interceptor.tscn`, do not copy its `metadata/_custom_type_script = "uid://…"` lines or its
  `unique_id=` values. Both are copied identifiers (CLAUDE.md: never copy a uid from a sibling). Omitting
  them is legal.
- **N7. Assert the bad-parent warning fired.** The bad-parent case (`3-plan.md:217`) is correct that
  `push_warning` does not fail a GUT test (`error_tracker.gd:67-76`, tests/README.md:465). It could also
  assert that the warning *was* recorded, via `get_errors_for_test()`, so that "stays inert **and says
  so**" is pinned, not just "no crash".
- **N8. Brain-driven fire on a rail.** The plan notes (`3-plan.md:132-134`) that a rail stops a
  brain-driven `AttackController`. Record it in DECISIONS.md for Phase 15, as the plan says. It is fine
  for Phase 1.

## Verified as correct
- **GDScript 4 does not chain virtual callbacks**, so the six `_physics_process` overrides are untouched.
  Their signatures (`(delta|_delta: float) -> void`) match the planned base, so there is no override
  mismatch.
- **Physics auto-enables before `_ready`.** Godot enables physics processing at READY, before the script's
  `_ready`, so `EnemyPathMover`'s later `set_physics_process(false)` still wins.
  `wave_manager.gd:183-208` attaches the path mover *after* `add_child(entity)`, so `_brain` and `_mover`
  are already resolved when `suspend_ai()` runs.
- **Duck-typed call compiles.** `_actor.suspend_ai()` on a `CharacterBody2D`-typed variable compiles; the
  same pattern is at `ai_targeting_module.gd:45`.
- **`get` on a missing property.** `actor.get("sprite_forward_angle")` returns null on a plain actor, with
  no error.
- **The facing arithmetic matches the path mover.** Heading RIGHT with the PI/2 default gives −PI/2, and
  `enemy_path_mover.gd:87` gives the same, `atan2(-1, 0) = -PI/2`.
- **`angle_difference` and `lerp_angle`** exist in 4.6 and are used correctly.
- **Roster A on `target_info.gd`.** Roster A does not match `info.velocity = (node as CharacterBody2D).velocity`
  (`target_info.gd:42`). `enemy_path_mover.gd` is not a substring hit for `enemy_mover.gd`. No `*_brain.gd`
  exists yet, so the new rosters start clean.
- **Load integrity only calls `can_instantiate()`.** It never instantiates or enters the tree, so the mover's
  `_ready()` warning cannot reach its tracker.
- **The existing `BaseEnemy` rosters stay clean.** Contact damage, hitbox and hurtbox geometry, and config
  isolation all sweep `assault/`, so the `tests/helpers/` fixture does not join them.
- **The F3 regression is caught.** An `if has_method … else <lookup>` form, or an early return, fails t2's
  real-LAS case unchanged. The fixture case pins that `suspend_ai()` is called.

# Round 2

VERDICT: APPROVED

I re-checked every round-1 finding against the revised `3-plan.md` (Revision 2). The float-timing figures were
re-run in headless Godot 4.6.3.

## Required findings

| # | Status | Where / how checked |
|---|---|---|
| R1 | Resolved | `3-plan.md:76-79`. `arrive` and `hold_position` pass `_decel() = braking if braking > 0 else acceleration`. This matches `step()`'s braking rule (`:91-93`) and `Steering.arrive`'s `v²/(2·accel)` radius (`steering.gd:26-35`). |
| R2 | Resolved | `3-plan.md:226-230`. There is one single-step `velocity == Steering.<x>(…)` case per wrapper, all nine, plus an `arrive` case that separates the 600 and 1200 decel rates. |
| R3 | Resolved, verified | `3-plan.md:202-204`, `:223-224`, `:247-249`. At `dt = 1/64`, run in the engine: `boost(…, 0.125)` is active for exactly 8 steps; `decision_interval = 0.25` gives 0 draws after 15 ticks, 1 after 16, and exactly 8 in 128. The 1/60 acceleration case (30 steps giving exactly 300) was already verified in round 1. |
| R4 | Resolved | See below. |
| R5 | Resolved | `3-plan.md:250-253`. The case starts at `velocity = (50, 0)`, asserts it is unchanged, and `free()`s the removed Brain. |

**R4 detail** (`3-plan.md:171-178`, `:186-188`):
- Roster A matches `velocity(\.[xy])?` and receiver `look_at(` / `rotate(`.
- Roster B matches bare or `self.` component writes and `look_at(` / `rotate(`.
- The boundary list gains `"actor.velocity.y += 1.0"`, `"actor.look_at(p)"`, `"velocity.x = 0.0"` and `"rotate(0.1)"` as hits.
- It gains `"var s := velocity.x"` and `"sprite.rotation_degrees = 180.0"` as non-hits.
- The `(^|[^\w.])` anchor keeps `Vector2.rotated(` and `base_enemy.gd:103`'s child-sprite write out of B.
- `gunship.gd`'s `velocity.x` idiom would now be caught if it ever landed in a swept file.

## Non-blocking notes from round 1

| Note | Status | Where |
|---|---|---|
| N1 | Folded in | Process-delta wording is corrected at `:265-267`, and the test actor uses FLOATING at `:202`. |
| N2 | Folded in | Sniper is now in the inherits-and-inert list at `:135`. |
| N3 | Folded in | `:241` and `:244-245`: direct-call cases never await, and the path-mover case never disables physics itself. |
| N4 | Folded in | Exactly 3 ticks for 3 frames, at `:240`. |
| N5 | Folded in | Full-path prefilter and `get_state()` node-0 script, at `:176-177`. |
| N6 | Folded in | No copied `unique_id` or `_custom_type_script`, at `:159-160`. |
| N7 | Folded in | Conditionally, at `:232`. |
| N8 | Folded in | DECISIONS.md entry, at `:271`. |

## Remaining notes (non-blocking; apply while implementing)

- **The arrive decel-rate case must build its expected value through the limits.** At `3-plan.md:228-230`,
  the case runs with `acceleration = 600, braking = 1200`, so the rate limit applies to the output of that
  same step. The resulting `velocity` is `actor.velocity.move_toward(Steering.arrive(pos, v0, target, speed,
  1200), rate·dt)`, not bare `Steering.arrive(…, 1200)`.
  - Compute the expected value that way, and give it a non-zero starting velocity `v0` (with `v0 = 0`,
    both radii are 0 and the two rates cannot be told apart).
  - Or pick a start point inside the 600-radius but outside the 1200-radius. There, the 1200 request is
    full speed and the 600 request is ramped, so their limited results still differ.
  - Do not "fix" a red result by dropping the limit.
- **The build-sequence doc line needs updating.** `3-plan.md:199` says "`DECISIONS.md` only for
  deviations", but `:271` now commits to a Phase 15 entry. Write that entry.
