VERDICT: APPROVED

## Round 2 (revision 2 of `3-plan.md`)

I re-checked revision 2 against every round-1 finding and the same criteria. B1 is fixed and so is every non-blocking item.
Nothing new blocks, so the plan is approved.

**B1, fixed.** The real-frame cadence row now runs at 4× with its own `_scale_clock(4)` (`3-plan.md:115`, `:134`):
- The risk note (`:131-136`) gives the measured numbers: headless sleeps about 6.9 ms per frame, so an idle frame at 8× is about
  0.055 game-s and 4 of 110 re-hits were refused; at 4× and 2× none were.
- It cites `tests/README.md` → Gate time rule 1, and the change from the epic's 8× is logged in `DECISIONS.md`.
- Gate time (`:137-138`): two rows of about 0.55 s real each, about 1.5 s in total. That is realistic for 2.1 game-s at 4× per
  harness and fits the +2.0 s allotment.
- The fallback is to share one scenario, never to go back to 8×.

**Non-blocking items, all fixed:**
- **N1:** the hand-ticked row uses `start(-1, 0.0)` (held), and the real row uses `start(0.0, 0.0)` and is cancelled after
  `round(2.0 / DT)` ticks. Both windows start on the first lethal tick (`:90-91`, `:117`).
- **N2:** the exact count and the exact `ceil(rehit_interval / DT − EPS)` = 33-tick spacing are asserted (`:91-92`). The ± 1 stays
  only on the real-frame row, as the epic wrote it. Hits land on ticks 0, 33, 66 and 99 of 120, which is 4 = floor(2.0 / 0.55) + 1.
- **N3:** the player's health is raised to 10 × `damage` (`:116`).
- **N4:** `SaveSandbox` is used in `before_all` / `after_all` (`:119-120`).
- **N5:** the static row also reads `HealthComponent.invincibility_time_in_sec` when that component's invincibility is enabled
  (`:112-114`).
- **N6:** `v_c` = `minf` of both players' `cruise_speed()`, read off-tree (`:127`). I checked that both values are right off-tree:
  - `player_fighter.gd:128-130` resolves its relative node path off-tree and returns 360.
  - `player_ship.gd:479` returns `max_speed`, which `_ready()` reads but never writes (`player_ship.gd:98-104`), so the off-tree
    value is 420.

  `r_p` = the larger of the two radii: fighter 14.5, ship 5 × 2.2 = 11.
- **N7:** the `BEAMS.md` notes are listed in the files table (`:25`).
- **N8:** the farthest-corner bounding radius, and the null-hurtbox handling (`hits_band` false, radius 0), are at `:64-66`.

**Remaining nit (non-blocking).** The exact count `floor(2.0 / rehit_interval) + 1` only holds if the 120-tick window includes its
end tick whenever `rehit_interval` divides 2.0 exactly. That case does not arise with 0.55, but write the window as inclusive, or
derive the expected count from the same tick arithmetic, so a later retune cannot mis-count.

---

# Round 1 (verdict then: CHANGES_REQUESTED)

Review of `3-plan.md` / `1-context.md` (t2, `EnemyBeam` core) against epic `cmug23ona0015m52w4t1m73bc/3-plan.md` §2.1–§2.3 and
"For every task". I checked the code and the Godot behaviour the plan relies on myself: scratch probes in `/tmp`, nothing in the repo
edited, Godot 4.6.3 headless.

The design is faithful and well specified. Every §2.1/§2.2 row and the static/sweep/lance §2.3 rows are present, and each has its
boundary. The swept-hit deviation is argued correctly. One blocking problem: the real-frame cadence row as specified will flake, and
the plan's reasoning for why it will not is wrong.

## Blocking

**B1. The 8× clock makes `test_player_cadence_on_real_frames` flaky, and the risk note's premise is false.**
`3-plan.md:116-118` says a re-hit can only be refused if one idle frame covers more than 0.05 game-s (6.25 ms real at 8×), and that
"headless GUT frames are far shorter". They are not:
- Godot headless sleeps `low_processor_usage_mode_sleep_usec` (about 6.9 ms) every frame, because the window cannot draw. The idle
  frame is therefore always longer than 6.25 ms.
- `tests/README.md:432-433` (Gate time, rule 1) already says "One idle frame at 8× is about 0.13 game-seconds". The same rule
  says a row whose tolerance is tighter than one idle frame "stays at a lower multiplier rather than widening the tolerance".
- Measured with a scratch probe of exactly this mechanism: a one-shot idle `Timer(0.5)` (as `player_base.gd:94-97,144-146`) started
  from a physics callback, with re-hits every 33 physics ticks (0.55 s at 1/60). Three runs, about 110 re-hits each:

| Clock | Physics steps per idle frame | Median idle delta | Refused re-hits |
|---|---|---|---|
| 8× | median 3, max 7 | 0.055 s | **4 of 110, every run** |
| 4× | median 2, max 3 | 0.028 s | 0 of 110 |
| 2× | median 1, max 2 | 0.014 s | 0 of 110 |

At 8× about 3.6 % of re-hits are refused. The row has roughly 3 re-hits per harness, so the pair fails on about 1 run in 5. Its
"delivered == health steps" assertion is exactly what such a refusal breaks. That turns the row into a flaky gate, not a guard.

Fix:
- Run this row at 4× from the start: copy the `_scale_clock()` pair with `_SPEEDUP = 4`. Rule 1 permits this; the epic's "8×" is
  a gate-time choice, not a design term. Log the deviation in `DECISIONS.md`.
- Rewrite the risk note with the measured numbers.
- Re-estimate gate time. At 4× the two cadence rows cost about 2 × 0.55 s real plus setup, not "≈ 0.6 s total". That still fits
  the +2.0 s allotment, but the plan must say so. If it does not fit, use a memoised shared scenario, never 8×.

## Non-blocking (fix while implementing)

**N1. The cadence rows must override the active duration.** `beam.tscn` ACTIVE is 1.2 s (epic §2.1 table). "2.0 s of ACTIVE" needs
`start(t, 2.0 + ignite_grace)`, or `0` (held) and then `cancel()`.
- `3-plan.md:84` (`test_rehit_cadence_over_two_seconds`) gives no override at all. With the scene's 1.2 s the beam lands 2 hits,
  so the row reads 2 against an expected 4 ± 1 and fails for the wrong reason.
- `3-plan.md:107` writes `start(0.0, …)` without saying what goes in the second argument.

State the override, and state where the counting window starts: the first lethal tick.

**N2. Tighten the hand-ticked cadence row.** Hand-ticked is deterministic, so "± 1" (`3-plan.md:84`) lets a 34-tick off-by-one
re-hit (0.567 s) pass, and even a 0.5 s cadence (5 hits). Assert the exact count and the exact tick spacing (33 ticks from
`rehit_interval / DT` with EPS). Keep ± 1 only on the real-frame row, as the epic wrote it.

**N3. Give the real-player rows health headroom.** `player_fighter.tscn:293-297` and `player_ship.tscn:224-225` both have 50 HP;
`damage` is 10.
- 4 hits leaves 10 HP.
- The "+1" tolerance would make it 5 hits = 0 HP. That triggers the ship's death path, which includes the Open Space ship's
  delayed scene reload (`player_ship.gd:567`).

Raise `max_health` / `current_health` on the instance before the row, or assert the count is ≤ 4 before the 5th hit could land.

**N4. Name the save sandbox.** Real player scenes run `SessionState.apply_to(self)` (`player_base.gd:103`). `tests/README.md`
→ House rules requires `SaveSandbox` `capture()` / `restore()`. `test_enemy_rockets.gd:42` does this; "patterns reused verbatim"
should name it.

**N5. Second i-frame source.** `Health` has its own opt-in i-frame (`health_component.gd:17-18,47`, 0.5 s, off in both player
scenes today). The static row (`3-plan.md:103`) reads only `PlayerBase.invincibility_sec`.
- Either add `invincibility_time_in_sec` (counted only when `invincibility_frames_enabled`) for both players' `HealthComponent`,
  or note that the real-frame row is what covers it.
- Note that the real-frame row only covers it at 4×; see B1.

**N6. Reading `v_c`.** `PlayerBase.cruise_speed()` already exists:
- `player_fighter.gd:128-130` returns `MovementStateMachine/MoveState.move_speed`.
- `player_ship.gd:479` returns `max_speed`, which is 420.

The epic says "the slower mode's cruise speed". Use `minf` of both instances' `cruise_speed()`: still 360 today, but it holds if the
ship is retuned. Note that the node path is `MovementStateMachine/MoveState`, not `StateMachine/…`.

**N7. Things to record in `BEAMS.md` (decided by the epic, worth stating):**
- The direct emit also bypasses `HurtBox.accepted_damage_types`. `big_asteroid.tscn:39` accepts only ROCKET from player fire, but
  a beam cuts it. That is consistent with `BeamBehavior` (`beam_behavior.gd:76-110`) and with `LaserRay`'s direct emit.
- A side barrel-roll (`dash_state.gd:112-115`, `HurtBox.monitoring = false`) does not dodge a beam, as it already does not dodge
  `LaserRay`.

**N8. `bounding_radius` on off-centre shapes.** "Half-diagonal of `get_rect()`" (`3-plan.md:60`) under-estimates a shape whose rect
is not centred on its origin, such as an off-centre `ConvexPolygonShape2D`. Every hurtbox in the project today is a Circle,
Capsule or Rectangle (checked: no `CollisionPolygon2D` or polygon shapes in any `.tscn`), so this is safe now. Using the farthest
rect corner from the shape origin costs nothing.

## Claims verified (no change needed)

- **`Shape2D.collide` is exact for scaled shapes.** A 2.7-scaled r5 circle against a 676 × 24 band hits at a centre offset of 25 and
  misses at 26 (reach 25.5). A triangle `ConvexPolygonShape2D` hits regardless of winding. So the ±1 px width/tip rows and the swept
  triangles are sound.
- **The swept-row deviation (`3-plan.md:87-90`) is right.** A 40 px tip jump leaves about a 19.6 px half-gap, inside the
  12 + 14 = 26 px band reach. The 0.2 rad step, with the `hits_band` "outside both bands" precondition, makes the row able to fail.
- **`Script.get_property_default_value` works at runtime.** `enemy_mine.gd` `trigger_radius` reads 80.0 and
  `player_base.gd` `invincibility_sec` reads 0.5; precedent at `test_enemy_mines.gd:605`.
- **`PackedScene.pack()` keeps the changed value.** Repacking an instance whose value was changed stores the non-default value on
  the root (e.g. `invincibility_sec 0.7`) and omits defaults. So `export_of_scene` plus a script-default fallback is consistent,
  and the synthetic boundaries work.
- **`inf` parses in `.tscn` text**, so LANCE's `rehit_interval = inf` is fine.
- **A code-built `top_level` `Line2D` gets the identity global transform** whether set before or after `add_child`, and inherits
  visibility. Global points draw correctly; `PiercingBeam` is the precedent.
- **Off-tree `global_transform` composes without an engine error in 4.6**, so reading `r_p` off an instance that is not in the tree
  is safe. `r_p` = 1 + 5 × 2.7 = 14.5, more conservative than `test_enemy_rockets.gd:40`'s 13.5.
- **Victim lookups resolve.**
  - `Hazards.hurt_box_of` (`hazards.gd:84-90`) finds `AllyFighter`'s child `HurtBox`; its property is `_hurt_box`.
  - The harness's fake player has no hurtbox, so `hits_band` / `bounding_radius` must tolerate `null`. Mention it.
  - `RamCorvette._on_received_damage` (`ram_corvette.gd:128-133`) refuses while armoured.
  - The fixture's `was_killed` path is `base_enemy.gd:242-249`.
- **Fairness terms with today's numbers pass the bounds, and each boundary fails as designed:**
  - static: 0.25 + 26.5 / 360 = 0.32 ≤ 0.9;
  - sweep: 0.8727 × 400 = 349 ≤ 360;
  - lance: commit 0.5 ≥ 0.5 and 1.0 − 0.5 ≥ 0.25.
- **Scope matches the task text.** TWIN, cover, strain drawing and hazard registration are declared minimal. `LaserRay` and
  `StationLaserPhase` are untouched.
