VERDICT: CHANGES_REQUESTED

Independent review of `3-plan.md` (t5, Space Fortress shell) against the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` ("For every task", §1.3,
§2.1, §2.2, §2.5.1–§2.5.7, §2.14–§2.16) and the code @ `f359dfa`. The design follows the epic faithfully: names, part table, sector wiring, ladder, death order,
EMP rule and brain shell all match, and nothing from t6/t7/t8/t9/t16 is built beyond stubs. Two findings make the gate go red as planned (F1, F2). Three
make test rows unable to fail (F3–F5). The rest are clarifications.

## Blocking

**F1. `tests/integration/test_base_enemy.gd` is missing from the roster-gate list, so as planned the gate goes red.**
`test_base_enemy.gd:74` `_sweep()` picks up every `<dir>/<dir>.tscn` with a `BaseEnemy` root, so `space_fortress.tscn` joins it automatically. Two of its
tables then fail:
- `test_lethal_damage_kills_and_frees_the_enemy` (`:154`) emits lethal damage on the root `HurtBox` and expects `died` and `queue_free`. The fortress root
  refuses all damage (`armor_deflected`), so the row fails unless `"space_fortress"` is added to `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW` (`:69`, where the
  carrier went in Ph10 t6, commit `7bdd10b`).
- `test_every_legacy_enemy_resolves_exactly_one_collision_contact_profile` (`:308`) defaults to COLLISION. The fortress authors ARMOR (§2.5.1), so it needs
  `"space_fortress": ContactProfile.Mode.ARMOR` in `_AUTHORED_CONTACT_MODES` (`:~304`).

Also expected by the carrier precedent, though not gate-breaking: bump `_MIN_ROSTER_SIZE` (`:62`, plus its comment list) and add `"space_fortress"` to the
every-phase tow refusers (`:544`). The epic §2.14 list omits this file too, so the task plan has to fill the gap. Add it to "Roster gates" and the build sequence.

**F2. Row 1's containment formula rejects the epic's own hangar.**
Row 1 requires "centre distance + shape radius / half-diagonal ≤ 176". For `Hangar` at (−150, 0) with a 36 × 56 rect, the half-diagonal is √(18² + 28²) =
33.29, and 150 + 33.29 = 183.3 > 176. The row fails on correct geometry. The real corners are at (−168, ±28), |·| = 170.3, so the part is inside, as epic §2.5.2
says ("Parts sit fully inside the hull circle"). Fix: test a rectangle's four transformed corners, and a circle by centre + radius. Also pin the rect as
`Vector2(36, 56)` (x radial): read the other way round, its corners (−178, ±18) sit at 178.9 px, outside the hull. Check one is batteries 140 + 22 = 162,
sweep 150 + 22 = 172, generators 146, core 44: all pass.

## Rows that cannot fail

**F3. Row 10 ("`.tres` values win over the scene's `Health`") passes even when the config is never applied.**
The plan authors part HP equal to the config (260 / 300 / 360 / 1500), so part `Health` equals the `.tres` whether or not the root's `_ready()` writes it.
`EnemyModule._ready()` (`enemy_module.gd:~95`) already writes `Health` from its own `max_health` export. Make it failable in one of two ways:
- Use the `test_carrier.gd:_spawn(props)` pattern: write distinct values on the private copy before `add_child` (e.g. `battery_health` 123, `core_health`
  1001) and assert part `Health`, the root `Health` and the module `max_health` export equal them.
- Leave the scene's part `max_health` exports at a value different from the config.

The same applies to row 4's sector params. `EnemyShield.regen_delay` defaults to 3.0 (`enemy_shield.gd:~60`), which equals `sector_shield_regen_delay`, so "from
config" is not observable for that field. Use a distinct private-copy value there too.

**F4. Row 6 checks the phase-held fields, never the visuals on screen.**
The "Clarification of §2.5.5" is right and consistent with the epic's intent. Epic §2.5.5 says snapshot keys are built "only from phase-driven state (what
`_on_phase_entered` … set[s]), never from which parts are alive". A generator's own `destroy()` sets its `Light` OFF (`enemy_module.gd` `destroy()`). That
happens on the very hit that enters `core_exposed`, so reading live light states would let that phase pass §25 on a part's death, which the epic forbids. A
blinking light, and t8's CHARGING door cycle (`boss_reinforcements.gd` header), would also change a live-state key with no phase change. Keep the
clarification and the DECISIONS line.

The cost: shutter and plating paths now come from `_shutters_open` / `_core_plating_open`, so a handler that sets the flag but never swaps the sprite still
passes. Row 6 (or row 5) must also assert the live consequences:
- after `shields_exposed`, every live generator's `Sprite.texture == shutter_open_texture`;
- one frame after `core_exposed`, the core's `Sprite.texture == core_open_texture`;
- a destroyed core is never swapped (the R2-4 rule the plan cites).

`Thrusters.visible` / `CriticalOverlay.visible` are already live.

**F5. Row 8's "mover halted (velocity zero)" is vacuous in t5.**
Nothing moves the fortress until t6, so its velocity is zero with or without `apply_emp`. Either give the mover a velocity first (a `request_velocity` and one
`mover.step()`, which is test code and outside the single-writer sweep), then assert zero after the pulse, or drop the claim. The 2.0 s window, the
still-tangible battery hit, and the dying branch are fine as written. The dying branch can fail both ways:
- `answers_emp()` returning `super()` only would take `EMPBlastModule._stun_enemy` (`emp_blast_module.gd:~47`) and disable `process_mode`;
- an `apply_emp` that does not return while dying would start a window (`base_enemy.gd` `apply_emp`).

Assert the fortress is still in `enemies` when the blast fires, so a later "leave the group on death" change cannot make the row pass vacuously.

## Clarifications (no redesign needed)

- **Row 3, bullet along y 0 from the left.** "Ending before the sweep battery" is ambiguous. If the bullet reaches `BatterySweep` (150, 0), the south bubble
  absorbs it and it is consumed. State the intent: either `range_px` ends at about x 100, or the row expects consumption at the sweep battery's bubble.
- **Geometry claims checked.**
  - A bullet down local x 60: the bullet capsule is about 2.4 × 5 px after its scale (`bullets/bullet.tscn`). It misses the core (r 44, gap 16), the
    generators (gap 34) and batteries at x ±99 (gap 17). It stays clear of every part hurtbox.
  - "Its shield bubble" is moot: `EnemyShield.radius` is draw-only (`enemy_shield.gd:67`). Absorption is through the part's own hurtbox absorber slot
    (`hurtbox_component.gd` `_on_area_entered`).
  - x 0 crosses `ShieldNorth`, `Core` and `ShieldSouth`, all locked, so `EnemyModule._resolve` deflects each and the bullet flies on.
  - `BeamBehavior` pierces every target within 12 px of the ray, so the beam row is right that all three ping.
  - The lane-row maths holds: capacity 120 / 50 per bullet gives three absorbed (the third breaks it), then the fourth damages the battery.
- **Root `_ready()` order works.**
  - Parts, `ModularHull` and `Brain` are ready before the root, and the brain's rng is seeded in `EnemyBrain._ready()`.
  - The root is not blocked in its own `_ready()`, so `ShieldSector` adding `EnemyShield` children to parts is legal (the Carrier does the same with mounts).
  - `phase_entered` is connected before `bind()`, so `batteries` reaches `_on_phase_entered`. `BossReinforcements` connects its own `phase_entered` first;
    harmless.
- **Optional.** A part killed during the 2.4 s death sequence can still enter `shields_exposed` / `core_exposed`, because part hurtboxes stay open. A
  `_on_phase_entered` early return while `is_dying()` would keep a corpse from swapping art. The epic is silent, so leave it to taste.
- **Nit.** The plan says "no HullMounts / PulseRing yet" but adds an empty `HullBeams`. That is harmless, but say why, or drop it to t16.

## Checked and fine

Names, part ids and sectors ("For every task"). Hull rule (`carrier.gd` deflects / armoured / `_on_received_damage`). Death order, latch, `Timer` child and
the `_finish_death` escort free (`space_station.gd`, `escort_container.gd`). `death_duration` as the duck-typed `BossDeathSequence` host contract
(`boss_death_sequence.gd` `_ready` / `_on_death_started`). The ladder validates under `boss_phase_driver.gd validate()`. The HEALTH-rule boundary 600 / 601
with `_RATIO_EPSILON`. `test_boss_phase_rules.gd`'s text pre-filter will see the script path in the hand-written `.tscn`. The config isolation identity row
matches `test_config_instance_isolation.gd:302`'s station row. `fortress_brain.gd` matches the single-writer sweep's `*_brain.gd` and must stay write-free.
Contact and hurtbox roster entries are needed and listed. The station is untouched. Gate-time plan within the 2.0 s allotment.

---

# Round 2

VERDICT: APPROVED

I re-reviewed `3-plan.md` (the *Roster gates* paragraph and the new *Revision 2* section) and checked it against the working tree:
`assault/scenes/enemies/space_fortress/{space_fortress.gd,.tscn,fortress_brain.gd,space_fortress_config.gd,.tres}`,
`tests/integration/test_space_fortress.gd`, and the `test_base_enemy.gd` / `wave_builder.gd` diffs. Every round-1 finding is resolved, and the
implementation matches the plan.

## Round-1 findings, resolved

- **F1, resolved.** The plan's *Roster gates* paragraph now lists `test_base_enemy.gd`. The diff adds `"space_fortress"` to
  `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW` (`:69`), adds `"space_fortress": ContactProfile.Mode.ARMOR` to `_AUTHORED_CONTACT_MODES`, raises `_MIN_ROSTER_SIZE`
  25 → 26 (with its comment list), and adds the fortress to the every-phase tow refusers (`:545`). This follows the Carrier precedent of `7bdd10b`.
- **F2, resolved.** `test_space_fortress.gd` `_reach()` (`:202`) measures a rectangle by its four corners. The scene authors `RectangleShape2D_hangar`
  `size = Vector2(36, 56)` (x radial), which gives 170.3 px, inside the hull. The new boundary (sweep battery moved to r 170 → 192 > 176) proves the check
  can reject.
- **F3, resolved.** Row 10 (`:646`) writes `battery_health` 999, `core_health` 1234 and `death_blast_count` 7 on the private copy before `add_child`. It asserts:
  - part `Health`, the module export and the root bar take those values;
  - `DeathSequence._blast_count == 7`, against a script default of 3 and a shipped value of 10, so a child that read the shared resource would fail.
  Row 4 (`:378`) uses 77 / 1.5 / 0.75 / 9.0 / 4.0, which differ from both the `.tres` values and `EnemyShield`'s defaults. `_apply_config`
  (`space_fortress.gd`) writes the part export and `Health` both, as the station does.
- **F4, resolved.** Row 6 (`:477`) asserts the live generator sprites equal `shutter_open_texture` (and differ from the intact one) after
  `shields_exposed`. It also asserts the live core sprite equals `core_open_texture` after `core_exposed`, and that `Thrusters` and `CriticalOverlay` are
  visible. Row 7 adds the "never over a wreck" check: core exposed and killed in the same frame → no plating swap. The snapshot clarification is
  consistent with epic §2.5.5. Row 6 now also checks that one generator's death and the blink itself leave the snapshot unchanged, the property the
  clarification exists for.
- **F5, resolved.** Row 8 (`:595`) sets `velocity` to (40, 0) before the pulse. `EnemyMover.halt()` zeroes `actor.velocity` (`enemy_mover.gd:158`), so
  "halted" is now observable. In the dying branch, the row asserts the wreck is still in `enemies` and that `answers_emp()` is true. It then fires a real
  `EMPBlastModule.try_activate`, and asserts that `process_mode` stays INHERIT, that no window starts, and that the wreck is freed after `death_duration`.
  Each assertion fails on the wrong build.
- **Row 3, resolved.** The bullet along y 0 starts at x −350 with a 400 px range, so it ends at x +50. That is 6 px past the core edge and short of the sweep
  hurtbox at 128, and "flies on" is asserted.
- **Dying guard and `HullBeams`, resolved.** `_on_phase_entered` returns while `_dying`. Ordering is safe: on a lethal core hit, the driver's
  `Health.amount_changed` listener runs inside `health.decrease()`, before `EnemyModule.destroy()` starts the death. `HullBeams` is gone from the scene.

## Also checked in the code

- `_ready()` runs in the planned order, ending `phase_entered.connect` → `bind()`, so `batteries` reaches the handler.
- `ShieldSector` children are added while the root is no longer blocked.
- Phase masks: 55 = MOVEMENT|ATTACKS|VULNERABLE|REINFORCEMENTS|VISUALS, 45 = MOVEMENT|VULNERABLE|ARENA|VISUALS, 51 = MOVEMENT|ATTACKS|REINFORCEMENTS|VISUALS.
  All three match §2.5.5.
- `constraint_mode = 1` is NONE. ContactProfile `mode = 4` is ARMOR with `shove_speed` 260. The root is layer 0 / mask 0. Body, hurtbox and contact share
  `CircleShape2D_hull`.
- `fortress_brain.gd` writes no `velocity` / `rotation` and overrides `on_emp_started()`.
- The blink row's hand-stepped sequence (0, 0.125, 0.125, 0.25 → COMMIT, COMMIT, OFF, COMMIT) is what `_process` produces.
- Homing tie-break (artillery vs missiles, exactly equidistant from (0, −400)) resolves deterministically to tree order, and a locked generator at 280 px
  would beat both, so the row can fail.

## Notes (non-blocking; for the implementation, not the plan)

1. **Copied UIDs.** `space_fortress.tscn` carries copied `uid://` values on its ext_resource references (shader, two PNGs, three component scripts). I
   checked each one: it decodes to its own path (`station_core.png.import` = `dkimdnfmfcosy`, `station_turret.png.import` = `dkxmbkyht3vj2`, matching
   `.uid` sidecars). They are correct references, not declarations. But CLAUDE.md says "never copy one from a sibling file", and the plan says "no UIDs
   typed". Either strip them (UID-less is legal) or let `test_resource_uid_integrity.gd` confirm them.
2. **Gate edits not yet in the tree.** These are planned but not yet in the working tree:
   - the roster entries in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd` and `test_enemy_hurtbox_geometry.gd`;
   - the fortress identity row in `test_config_instance_isolation.gd`;
   - the "contains `space_fortress.tscn`" expectation in `test_boss_phase_rules.gd`.
   They are required by the acceptance criteria.
3. **Nit.** Row 11's `assert_false(phase_ids.has(&"station"))` cannot fail meaningfully. The naming rule is better served by the docs or by dropping it.
