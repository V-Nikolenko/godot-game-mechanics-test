VERDICT: CHANGES_REQUESTED

Independent review of `3-plan.md` (Phase 9 t7, Jamming Structure) against the approved epic plan
(`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.8, §2.9, §2.15, "For every task"), `DECISIONS.md` (Phase 9) and the
code at HEAD. The design matches the epic, and the code paths it relies on behave the way the plan says, with two exceptions
(finding 2 and finding 3). One row that an earlier task deferred to t7 is missing (finding 1). All the fixes are small. None
needs a redesign.

## Must fix

1. **A deferred t11 row is missing: "a jammer the EMP zone reaches goes quiet".**
   `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md:3657` (t11) says this row "waits for `JammingStructure` (t7) and is
   not in `test_emp_zone.gd` yet". Epic §2.13 (`3-plan.md`, the `EmpZone` bullet) and §2.8 ("the hub EMP zone and a placed
   EMP mine all switch a jammer off") both state the behaviour. `assault/scenes/hazards/emp_zone/emp_zone.gd:34` emits
   `TARGET_ALL`, and `global/components/emp_pulse.gd:35-43` routes enemies by `answers_emp()` and centre distance
   `<= radius`. So the code path exists, but no row covers it, and the t7 plan does not mention it. Add a row to
   `tests/integration/test_emp_zone.gd`, now that the class exists:
   - a local jammer whose centre is inside the zone's 260 px goes quiet on the TELEGRAPH -> ACTIVE edge;
   - it stays quiet for 2.0 s (120 ticks under the clock rule) and is lit again after that;
   - boundary: a jammer whose centre is 1 px outside 260 stays lit.
   Add it to the build sequence and to the gate-time estimate.

2. **The pulsed-phase tick numbers in row 2 are wrong at two of the four edges.**
   `HazardField` accumulates the cycle with `_cycle_clock = fposmod(_cycle_clock + delta, _cycle_length())`
   (`global/hazards/hazard_field.gd:98`) and compares with `<` (`:162-166`), so float drift moves the edges. I ran the exact
   accumulation (`fposmod`, `delta = 1.0 / 60.0`, 0.8 / 3.0 / 2.5) in headless Godot 4.6. The phases change at:
   - **48** -> ACTIVE (clock 0.8);
   - **229** -> QUIET (clock 3.8167, so tick 228 is still ACTIVE);
   - **379** -> TELEGRAPH;
   - **427** -> ACTIVE (second cycle).
   The plan says "ACTIVE ... to 227 (3.8 s), QUIET until 377 (6.3 s)", which is one tick early at both of those edges. Correct
   the text. Then either pin the exact ticks (48 / 229 / 379 / 427), which is deterministic and can serve as the boundary, or
   state a ±1-tick tolerance on each edge explicitly. The Ph9 lock row `test_player_ability_lock.gd:314-347` avoids the issue
   by looping on `phase()`.

3. **Snipers and Fighters will not choose positions inside a jammer field, which contradicts "their own ground".**
   Every row in the plan concerns *motion*, and motion through the field is unchanged (see finding 7). But two *spot
   selectors* reject any hazard info regardless of `avoid_weight`:
   - `assault/scenes/enemies/sniper/sniper_brain.gd:550-557`: in a firing-point candidate, any non-blocker info within
     `hazard_margin` (90) sets `hazard_ok = false`, and `_survives()` (`:571`) drops that point.
   - `assault/scenes/enemies/fighter/fighter_brain.gd:882-886` (`_inside_other_hazard`): any info other than the wreck
     itself rejects a cover point.

   With a jammer registered, a Sniper therefore never takes a firing point within `field_radius + 90` of a jammer. For the hub
   sector jammer (t13) that is 730 px, against a 900 px Open Space ring. A Fighter likewise never hides behind a wreck inside
   a field.

   This contradicts DECISIONS.md:3462 ("enemies treat it as their own ground"), epic §2.9 ("every enemy ship moves through it
   as if it were empty space ... Placement puts shooters around jammers") and the plan's own Problem section. The plan has to
   choose one of two options and record the choice in DECISIONS:
   - (a) Skip `info.kind == &"jammer"` in those two filters. This is bit-identical for every Ph4–Ph8 hazard, because none of
     them has that kind. Add one Sniper row: a firing point inside a lit local jammer survives, and the same point inside a
     gravity well still does not.
   - (b) Keep the behaviour and log it as a deviation, with the reasoning, before t13/t14 place shooters around jammers.
   Option (a) is cheap and matches the epic.

## Should fix (test strength)

4. **The corvette row (13) does not cover a natural PURSUIT choice.**
   `missile_corvette_brain.gd:400-414`: `choose_kind()` returns PURSUIT for a fleeing player (`player_speed >=
   pursuit_flee_speed and radial > 0`), separately from the 1-in-4 DUMB->PURSUIT swap. The planned cases are dumb (swap),
   cluster and warhead. An implementation that only suppresses the swap and downgrades CLUSTER would pass all three and still
   fire Pursuit salvos at a fleeing player inside a field.
   - Add a "pursuit" case (player velocity radial-outward above `pursuit_flee_speed`): 200 DUMB inside the field, 200
     PURSUIT in the control 600 px away.
   - The downgrade itself (after the swap, `Hazards.count() > 0` first, no rng draw added) is correct and keeps the swap rng
     sequence.

5. **The Fighter row (5) has no positive control.**
   "Equal to the no-jammer run" plus "the path enters the field" can fail on a non-zero `avoid_weight`. But nothing proves
   that avoidance is actually live in that setup: the harness, the Fighter's `hazard_avoidance` 0.8 copied in
   `base_enemy.gd:109-112`, and the lookahead reaching the field. Add the cheap control: the same field with `avoid_weight`
   1.0 changes the path (or reuse the `_fighter_past_a_well` control shape). `test_emp_zone.gd:254`
   (`test_a_fighter_bends_round_a_zone_and_ignores_a_zero_weight_one`) is the precedent.

6. **Row 3: say when the exit tick T is sampled.**
   `BaseEnemy._on_health_changed` (`base_enemy.gd:319-336`) sets `was_killed` and calls `queue_free()`. The `Field` stays
   registered until the deletion flush, so a sample taken right after `was_killed` is still "inside", and T would be one
   sample later than the row claims. Specify: sample T only after `not is_instance_valid(jammer)` and
   `Hazards.jammer_at(p) == null`. The draft test already does this; the plan text should say it.
   Similarly, row 10 ("field clock frozen while it flies") only holds if the jammer root, `Field` and `AssaultDrift` have
   physics processing off. State it; otherwise the 8× real frames advance both suppression clocks.

## Minor / notes

7. **Verified, no change needed:**
   - **Fighter path bit-identity.**
     - `EnemyMover.step` (`global/enemy_ai/enemy_mover.gd:222-252`): with the jammer registered, `hazards_live` becomes
       true, but the movement stays identical:
       - `penalty_at` = 0, so the factor 1.0 is not `< 1.0` and nothing is scaled.
       - `_avoid` calls `Steering.context_avoid`, which skips `avoid_weight <= 0` (`steering.gd:250`). All danger stays
         0, so the clear-way test returns `desired` (`:289-290`). The non-zero `_avoid_prev` is only read when the way is
         not clear.
       - `HazardDrift.step` with a zero accel snaps to ZERO (`global/hazards/hazard_drift.gd:14-19`), so `d` is not
         added.
     - The Fighter brain:
       - `_take_cover` runs (`fighter_brain.gd:695`, `:745-772`), finds no `wreck`, and draws no rng.
       - Its extra `_derive_pass` call is idempotent within the tick (`:561-628`).
       - `_mates()` skips the jammer, which has no `Brain` (`:1780-1786`).
   - **Ph5 rocket rows.** The skip sits behind `Hazards.count() > 0` (`enemy_rocket.gd:276-279`). With no hazard it is the
     old path. With only non-jammer hazards (the Ph6 projectile rows), `jammer_at` returns null. Either way the result is
     bit-identical. Inside a QUIET field, `bend_heading` returns the heading unchanged because accel is ZERO
     (`hazards.gd:55-65`), so row 7 holds exactly.
   - **Lock timing T+44 / T+45.** `player_base.gd:290-307`: the exit tick sets `_stabilise_left = 0.75` with no decrement,
     and 0.75 − 45·(1/60) = −6e-16 ≤ 1e-6. So the player is locked at T+44 and unlocked at T+45, for both the kill row and
     the direct `try_activate` row.
   - **Suppression clocks.** 5.0 s ends on tick 300 and 1.0 s on tick 60, which matches the unit row (false after tick 59,
     true after tick 60) and sits inside the "quiet after 299 / lit by 301" bound.
   - **Clock order.** The engine runs the root's physics before its child `Field`. Both clocks start at the same value in
     the same `apply_emp` call and use the same rule, so `is_emp_disrupted()` and `is_suppressed()` end on the same tick
     whatever the order. Hand-tick both, root first, as the draft `_step()` already does.
   - **World-anchored x.** It is the same expression and the same `_ready()` placement as `turret_group.gd:65-68`.
     `WaveManager` sets `global_position` before `add_child` (`wave_manager.gd:197-209`), so the shift is not overwritten.
   - **EMP Blast.** `emp_blast_module.gd:39-46` needs no code change.
   - **`super.apply_emp()`.** It returns early on a refresh (`base_enemy.gd:181-183`), so `field().suppress()` must be
     called unconditionally after it, as the plan writes it.

8. **`restart_cycle()` is harmless but untested.**
   No physics tick separates `Field._enter_tree()` (`hazard_field.gd:77-85`) from the root's `_ready()`, so `_cycle_clock` is
   already 0, and in the shipped scenes the call reduces to `_refresh_info()`. It only does work for a config overridden
   before `add_child`, and no row exercises that case. Either:
   - add one row (a pulsed jammer whose config cycle / radius are overridden before `add_child` registers the override's
     radius and phase at once), or
   - replace it with a plain public refresh.
   Not blocking.

9. **The Cluster split still aims at the predicted point inside a lit field** (`enemy_rocket.gd:321-350`). Only `_steer` is
   skipped, which is what the epic specifies. Noting it so the ENEMY.md text does not claim "Cluster rockets are blind
   inside".

10. **Coverage check against the acceptance list.** Each item maps to a row, provided findings 1–6 are folded in:
    - per-variant info and the config / scene match: row 1;
    - pulsed phases: row 2 (with the finding 2 fix);
    - shoot it dead from inside: row 3;
    - drift and anchoring: row 4 (with its Open Space control);
    - the Fighter: row 5;
    - Pursuit straight / steer: row 6;
    - the corvette and its control: row 13 (plus finding 4);
    - the roster gates: §2.15 entries, including `_MIN_ROSTER_SIZE` 20 -> 23, `_AUTHORED_CONTACT_MODES`, `no_hitbox` in
      both contact files, the hurtbox ROSTER, the dual-mode row, and the `ENEMIES_CLEARED` / sector-in-Assault guards. The
      config-isolation sweep is satisfied by one `*config*.tres` per directory, with the sector and pulsed scenes overriding
      `config`, as `heavy_emplacement/` does.
    - the four EMP rows: rows 8 and 10–12.
    No sweep I checked is tripped by an untextured `Polygon2D` hull: sprite transparency, hurtbox / contact geometry, the
    base-enemy flip row and collision-layer names (bits 1 / 512 / 65 are all named). The gate-time allotment of 2.7 s looks
    sufficient for the three 8× rows.

## Round 2
VERDICT: APPROVED

Re-checked each round-1 finding against "Revision 1", the corrected row 2 and the code at HEAD. I also read the WIP drafts
(`tests/integration/test_jamming_structure.gd`, the t7 sections of `test_emp_zone.gd`, `test_emp_blast_module.gd` and
`tests/unit/test_hazard_field.gd`) to confirm the rows can fail. Every finding is resolved. The revision adds no new problem
that blocks implementation. Items 1, 3c, 3d and 8 below are small corrections to make during implementation, not another
review round.

1. **Finding 1 (EMP zone reaches a jammer): resolved.**
   - `emp_zone.gd:34` emits `TARGET_ALL`, and `emp_pulse.gd:40-46` routes by `answers_emp()` with a centre distance
     `<= radius`. The zone scene radius is 260 (`emp_zone.tscn:13`).
   - The plan's 259 / 261 split is consistent with that rule, and so is 2.0 s = 120 ticks under the `<= 1e-6` clock rule
     (quiet after 119 ticks, lit after 120).
   - Text mismatch: the draft row (`test_emp_zone.gd:291-312`) puts the near jammer at exactly +260, on the edge, and the
     far one at -261. 260 is the stronger boundary because it tests the `<=` itself. In the Assault harness the jammer's
     world-anchor shift is exactly 0 (`arena_camera.gd:88-104`, both rects centred on the camera), so 260.0 stays exact.
   - Fix: change the plan text to 260 / 261 so the plan and the test agree.
2. **Finding 2 (pulsed ticks): resolved.** Row 2 now pins 48 / 229 / 379 / 427, and the draft asserts exactly those ticks
   (`test_jamming_structure.gd:193-231`).
3. **Finding 3 (spot selectors): resolved by option (a).**
   - **a. Call-site coverage is complete.** I swept every `Hazards.around` call outside tests. The three sites the revision
     changes (`sniper_brain.gd:554`, `:634`, `fighter_brain.gd:884`) are the only ones that reject on *any* info. The
     others are safe as they stand:
     - `ram_corvette_brain.gd:390-391` filters to `gravity_well`.
     - `mine_layer_brain.gd:817-819` and `enemy_mine.gd:227` filter to `mine`.
     - `sniper_brain.gd:576` and `:591-592` take blockers only.
     - `enemy_mover.gd:287` feeds `context_avoid`, which skips `avoid_weight <= 0`.
   - **b. Existing rows are bit-identical.** No test at HEAD combines an AI Sniper or Fighter with a `jammer`-kind field.
     The only test files with jammer fields use the *player* fighter (`test_player_ability_lock*.gd`,
     `test_seeking_ordnance.gd`). The `test_sniper.gd:1546` well row uses kind `gravity_well` and is unaffected.
   - **Both new rows fail on HEAD:**
     - Sniper: every in-field candidate's `hazard_ok` is false on HEAD, and the chosen point moves.
     - Fighter: the jammer info is "other", so `_inside_other_hazard` returns true.
     - The fighter row also has its own in-row well control.
   - **c. Minor (sniper row).** The row's only control is the cross-file well row. Give it the same in-row control the
     fighter row has: a `kind = &"gravity_well"` stand-in (the `test_sniper.gd:1477` `_well` shape) at the same point marks
     the in-reach candidates `hazard_ok == false`. That keeps the row self-proving if the other file changes.
   - **d. Minor (sniper row).** The draft centres the jammer *body* on the control point
     (`test_jamming_structure.gd:563`), so the row ends up blessing a firing point inside the tower's r 28 body. Root
     bodies are layer 1 / mask 1, so a real sniper could not reach that point.
     - Fix: offset the jammer about 120 px from the point. The field (r 240 + 90 margin) still covers it.
     - Gap after the skip: nothing keeps a sniper's point off a jammer body. Turrets and emplacements have the same gap
       today, so this is not a blocker. Note it in ENEMY.md.
4. **Finding 4 (corvette Pursuit case): resolved.** `choose_kind` returns PURSUIT at `missile_corvette_brain.gd:186`,
   ahead of the swap. 350 px/s is above `pursuit_flee_speed` 300.
   - Set-up requirement: the offset must be at least `warhead_range` 420 (`:184` returns WARHEAD first). Use offset 600
     with velocity `(0, 350)`, away from a corvette at `(640, 0)`.
   - State the offset in the row so an implementer does not reuse the warhead case's 300.
5. **Finding 5 (Fighter positive control): resolved.** `_refresh_info()` copies `avoid_weight` for every non-QUIET phase
   (`hazard_field.gd:186`), so the draft's write followed by `restart_cycle()` (`test_jamming_structure.gd:368-374`) does
   reach the registered info. An always-on field never enters QUIET.
6. **Finding 6 (timing statements): resolved.**
   - Row 3's T is sampled after `not is_instance_valid(j)` and `jammer_at == null` (draft `:276-279`).
   - Row 10 freezes the root, `Field`, `Field/Art` and `AssaultDrift` (draft `test_emp_blast_module.gd:162-171`). Its
     299 / 301 bounds bracket tick 300.
7. **Finding 8 (`restart_cycle()`): resolved,** with one condition.
   - The integration row (`test_jamming_structure.gd:507-522`) writes `j.config` between `instantiate()` and `add_child()`.
     That copy is private only because the *local* scene does not author `config`, so `BaseEnemy._init()`'s
     `privatise()` copy survives.
   - For `sector_jammer.tscn` / `pulsed_jammer.tscn` (which do author `config`, plan §5), `j.config` at that moment is the
     shared cached `.tres` until `_enter_tree()`.
   - Fix: add `assert_true(j.config.resource_path.is_empty(), "the private copy")` before the writes, or state in §5 that
     the local scene must not author `config`. Otherwise one editor resave turns the row into a write to the shared
     resource, which then corrupts row 1's table check later in the same run, depending on test order.
8. **Finding 9 (Cluster note): fine as written.**
9. **Unit rows.** The `test_hazard_field.gd` suppress draft checks out:
   - It pins the longest-wins rule correctly: a second `suppress(0.25)` at 0.5 s remaining leaves the window ending on
     tick 60.
   - Its gravity-well bit-identity row covers every `_refresh_info` field.
