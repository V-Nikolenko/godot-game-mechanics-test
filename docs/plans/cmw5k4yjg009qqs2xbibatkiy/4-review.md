VERDICT: APPROVED

# Review: Phase 9 t1, the player-side ability lock (`3-plan.md`)

Independent review against the epic plan (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`: "For every task", §2.1, §2.2, §2.18), the
acceptance criteria, CLAUDE.md and `tests/README.md`. I checked the code the plan names myself and probed the uncertain engine mechanics in a
throwaway Godot 4.6.3 headless project outside the repo (since deleted).

## What I verified (no finding)

- **The design matches §2.1.** The API names and signatures are the same, and so are the field names (`_in_field`, `_field_stabilise`,
  `_stabilise_left`, `_stabilise_total`, `_timed_left`). The exit-tick rule (no decrement on the exit tick), longest-wins timed lock, the
  `_tick_clock` epsilon, the early return `Hazards.count() == 0 and not abilities_locked()`, the three seams, the check order in
  `RocketState` (cooldown first, then the lock) and "WeaponState not edited" all match §2.1. The plan settles two things §2.1 left open and
  says so: `_report_lock()` emits at the `apply_ability_lock()` call, as `apply_emp` does, and `_lock_reported` tracks the edge.
- **Existing behaviour stays bit-identical.** With no hazard and no lock, the step reads state and writes none. With non-jammer hazards
  present (as in `test_player_hazards.gd` and `test_enemy_mines.gd`, which hand-tick real players beside launched mines), `jammer_at`
  returns null. The only writes are `_tick_clock(0.0, D) = 0.0`, and no signal fires. None of the `hazard_info()` implementations
  (`HazardField`, `EnemyMine`, `Wreck`, `DebrisFragment`, `LaserRay`, `EnemyBeam`, the test fixtures) has a side effect beyond refreshing
  `position`. `test_ram_corvette.gd` calls `_launch_*` directly on a bare `CharacterBody2D`, so the K seam never reaches it. The Ph7 H rows
  call `_input` on unlocked ships, so `allow_ability_press()` returns true and their path is unchanged. The new `HazardField` exports
  default to false / 0.0.
- **`HazardField` refresh.** `_refresh_info()` runs in `_enter_tree()` (hazard_field.gd:79). A field built from props before it enters the
  tree is therefore lit with no tick. `hazard_info()` re-reads `position` on every call (hazard_field.gd:134), so moving the field or the
  ship needs no refresh. The pulsed row ticks the field by hand and reads its edges from `phase()`, which is correct.
- **Clock arithmetic** (probed in Godot doubles):
  - 1.5 s minus 90 steps of `1.0/60.0` leaves a positive residual, and so does 2.0 s minus 120 steps. Without the epsilon, both locks would
    end one tick late.
  - 0.75 s minus 45 steps reaches ≤ 0, and minus 44 steps leaves 0.01667.
  - "1.5 s, then 0.5 s at tick 30" and "1.0 s, then 2.0 s at tick 30" end on ticks 90 and 150.
  - So every exact-tick row in the plan holds, and the epsilon row really fails without the epsilon.
- **Duck-typed call on the typed `actor: CharacterBody2D`.** `actor.has_method(&"allow_ability_press") and not actor.allow_ability_press()`
  compiles and runs (probed), which matches the `ai_targeting_module.gd:40-45` precedent.
- **`Viewport.push_input()`** (probed). It dispatches an `InputEventAction` to `_input` synchronously, and `is_input_handled()` is true
  afterwards when a handler consumed the event. The only `use_ability` consumers in the project are the two ship `_input`s.
  `DialogPlayer._unhandled_input` returns early when inactive. The "one ship in the tree per push" rule is right, because
  `_call_input_pause` stops at the first handler.
- **Spend probes.** Each of the 10 `try_activate` overrides has a real "spent" probe that a refusal leaves untouched and an acceptance
  flips:
  - `_active` for trajectory_calc and final_resort.
  - `_cooldown_left` for emp_blast, plasma_nova, overheat_nullifier and ai_targeting.
  - `_active or _cooldown_left` for parry.
  - `_passive_lockout` for cockpit_heal.
  - `temporary_count` for shield_overload (`Shield.add_temporary()` exists).
  - `engine_boost_active` for engine_boost.
  - The exception (Open Space never fires the Boost Drive on H) is handled correctly.
- **Side effects the plan already accounts for** (ai_targeting and emp_blast aside, see findings 3 and 4):
  - trajectory_calc's acceptance sets `Engine.time_scale` (restored by `mod.remove()` and `after_each`).
  - plasma_nova adds a root `CanvasLayer`.
  - Rings, ghosts and overlays land in the ship's parent box.
  - Rockets are children of `RocketState`.
  - The `CooldownTimer` and the dash timers are node `Timer`s.
- **The beam row works hand-ticked.** `BeamBehavior.tick` hits targets geometrically (a node in group `enemies` with a `HurtBox`, within
  12 px of the segment) and only raycasts for blockers (beam_behavior.gd:56-115). The 300 px dummy is hit, and the other ship's dummy
  1200 px to the side is not. `seed(tick)` before each ship's weapon tick covers every RNG draw: straight jitter, spread pellets and
  sniper angles (`randf_range` and `randi`).
- **CLAUDE.md and README conventions.**
  - Both signals are declared with their arity (`test_signal_emit_arity.gd`).
  - There are no prints.
  - The save sandbox and the `ShipModuleState` snapshot follow the Ph7 file.
  - No hand-typed UIDs.
  - `check-test-leaks.sh` is in the build sequence.
  - The gate-time "before" figure is measured on a clean `git archive` copy.
  - DECISIONS and the docs skill are in step 6.
- **Coverage.** All 13 rows of §2.2 are present, and every clause of the acceptance criteria maps to a named test. The plan adds a
  Shift-path Boost Drive row (a §2.1 "never locked" item) and an anti-inert row through each ship's own `_physics_process`, including the
  Assault dialog early return.

## Findings

1. **Minor: the movement row has no check that the verbs actually ran.** (`3-plan.md:143`; `player_ship.gd:373`;
   `dash_state.gd:43-64`)
   - **Problem.** The row asserts only that A equals B and that B is locked. A run where the Shift boost, the turn, the dash or the warp
     never happens on either ship is still equal, so the row passes without showing the verb is unlocked. The primary-fire row has a
     non-vacuity check ("each mode records at least one shot"); this row needs one too.
   - **Fix.** Assert on the control ship A:
     - Open Space: `_boosting` becomes true on tick 10, `velocity.length() > max_speed` on that tick, `rotation` has moved from its start,
       and the ship has been displaced.
     - Assault: the movement machine's `current_state` is `DashState` from tick 20, `velocity.y < 0` while dashing, and the warp moved the
       ship exactly 120 px.
   - Equality with B then proves B ran each verb too.

2. **Minor: `just_pressed` behaves differently in a physics frame, and GUT does not guarantee an idle frame.** (`3-plan.md:139-143`;
   `weapon_state.gd:111,120`; `player_ship.gd:373`; `addons/gut/gut.gd:848-853`)
   - **Probed.** In Godot 4.6.3, `Input.action_press()` followed by `is_action_just_pressed()` returns true in idle code but **false**
     inside a physics frame, because the pressed physics frame is set to the next one.
   - **Why it matters.** GUT runs test bodies wherever the previous `await` resumed. It only awaits `process_frame` between tests when
     `paint_after` (0.1 s) has elapsed, so a synchronous test is not guaranteed to start in idle context.
   - **What breaks.** The sniper path (`just_pressed` / `just_released`) and the Open Space Shift boost (`just_pressed("boost")`) depend on
     that edge. The sniper's "at least one shot" assertion could go red depending on which file ran before. The boost would silently
     never fire, which ties into finding 1.
   - **Fix.** Start both lockstep tests with `await get_tree().process_frame` before building anything, so no ship or field ticks during
     that frame. Nothing else in them awaits, and `check-test-leaks.sh` already runs.
   - **Header comment.** Say that within one process frame `just_pressed` and `just_released` stay true on every tick (non-legacy
     semantics, confirmed). The sniper therefore re-arms on every tick, and fires on tick 0 if "shoot" was released earlier in the same
     frame. That is fine because only A == B is asserted, so add no sniper count or timing expectations.

3. **Minor: the "no `enemies` node" premise is assumed but not asserted.** (`3-plan.md:131,155`; `emp_blast_module.gd:245-249,269`)
   - **Problem.**
     - EMP Blast's acceptance disables every non-immune node in group `enemies` and creates a 5 s `SceneTreeTimer` for each.
     - Plasma Nova and Shield Overload also act on that group.
     - The ai_targeting dummy is the only `enemies` node in the H rows, but the plan does not say it lives in the per-id box.
   - **Fix.** Make the dummy a child of the box that is freed per id. Assert `get_tree().get_nodes_in_group(&"enemies").is_empty()` before
     the emp_blast, plasma_nova and shield_overload acceptances, and in the H-boundary and no-hazard rows. The Risks claim then becomes
     enforced rather than assumed.

4. **Minor: in the K row, a cooldown can masquerade as the lock.** (`3-plan.md:134`; `warhead_missile_shooting_state.gd:43-45`; both
   `.tscn` files set `CooldownTimer` `wait_time = 5.0`, `one_shot`)
   - **Problem.** The post-unlock warhead launch starts the 5 s `CooldownTimer`, which never advances in a hand-ticked test. On the same
     `RocketState`, the homing "after the unlock the same call launches" would then be refused by the cooldown, not the lock.
   - **Fix.** Use a fresh ship per rocket type, or call `cooldown_timer.stop()` and `select_sub_weapon(1)` between the two.
   - Assert `cooldown_timer.is_stopped()` before every locked press, so each refusal is attributable to the lock alone.
     `test_k_during_the_cooldown_is_not_a_refusal` covers the opposite case.

5. **Note: the never-affected rows use a far-away field as their control.** (`3-plan.md:142-143`)
   - The epic's §2.2 words the control as "no field". The plan's control keeps the same field registered but out of range (1200 px; moved
     5000 px away before A's tick).
   - This is the better isolation. Both runs take identical `Hazards.count() > 0` paths (`_step_hazards`, the Assault drift block,
     `hazard_speed_factor()`), so any difference can only come from the lock. The `count() == 0` path is covered separately by the
     no-hazard row.
   - **Fix.** Record this reading in DECISIONS "Phase 9, built in t1" so it does not look like a silent deviation.

6. **Note: the gate-time ship count is low.** (`3-plan.md:157`)
   - By the plan's own rows, the file instantiates closer to 80–90 ships, not ~40:
     - 2 × 10 per-module ships,
     - ~2 × 12 timing ships,
     - 2 × 3 for K,
     - 6 for movement,
     - 4 to 20 for primary fire, depending on whether ships are reused across modes,
     - plus the rest.
   - Ph7's `test_player_boost_disruption.gd` ran about 50 ships in ≈ 0.5 s, so 2.0 s is still plausible.
   - **Fix.** Time the file on its own first, and apply the stated fallback (share one ship per mode) before cutting anything.

7. **Note: two cheap rows are optional, outside §2.2.** (`3-plan.md:70`; epic §2.1 "Overlapping fields")
   - Overlapping fields: leaving the inner of two fields keeps the lock and starts no delay. Today only the unit `jammer_at` row covers
     this.
   - Assault: a locked H press during a dialog is ignored, with no refusal and not handled. The plan states the behaviour, but no row pins
     it.
   - Both are a few lines each. Add them if gate time allows.

8. **Note: count signals by appending to an Array.** Record every signal by appending to an `Array`, as the Ph7 file does
   (`got.append(...)`). A lambda that increments a captured local `int` changes only its own copy, and the count would stay 0.

## Summary

The plan builds exactly what §2.1, §2.2 and §2.18 ask for, with the epic's names and timing. Every §2.2 row and every acceptance clause is
present and buildable headless, and existing tests stay bit-identical. I confirmed the mechanics it depends on: the clock arithmetic, the
duck-typed call, `push_input` dispatch, field refresh and the module probes. The four minor findings are test-robustness fixes the
implementer can absorb without re-planning:
- non-vacuity checks in the movement row,
- an idle-frame start for the two lockstep rows,
- asserting that no `enemies` node exists before the area-effect acceptances,
- keeping the K cooldown from masquerading as the lock.

None of them changes the production design.
