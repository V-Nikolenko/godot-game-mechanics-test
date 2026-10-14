# Review round 1
VERDICT: CHANGES_REQUESTED

Reviewed `3-plan.md` (Revision 1) and `1-context.md` against the code at HEAD `5505090`. I read
`ram_corvette_brain.gd`, `ram_corvette.gd`, `ram_corvette_config.gd/.tres`, `ram_corvette.tscn`, `enemy_mover.gd`,
`steering.gd`, `engagement_budget.gd`, `target_info.gd`, `enemy_brain.gd`, `contact_profile.gd`,
`armor_plate.gd::set_glow`, `state_light.gd`, `assault_corridor_constraint.gd`, `base_enemy.gd::suspend_ai`,
`enemy_path_mover.gd`, the 22 ram rows in `level_1_director.gd`, `test_ram_corvette.gd`, the ram cases in
`test_enemy_dual_mode.gd`, `test_sniper.gd`'s attack-in-budget harness, the Swarm and Gatling gate precedents, the
single-writer gate's patterns, epic §2.6.1–§2.6.3, §2.9.4 and the §4 t17 row, and DECISIONS Phase 4 / t16.

Most of the plan holds up against the code:
- The contact rules match epic §2.6.3: ARMOR stays armed while plates remain. Once exposed it is armed only in CHARGE.
  The shove comes from `armor_shove_speed` and is zeroed by `_expose`.
- STAGGER as an appended enum value is consistent with t16's "values fixed" and with t19, which only appends hub
  phases and never names a STAGGER value.
- The braking field exists and the mover honours it (`enemy_mover.gd:41`, `:195-196`).
- The side-offset geometry is right at the level-1 spawn distance. I re-derived the ring crossing at (180, −379) from P,
  which is 25° off vertical. With the stub 200 px away it is 28°, and the top-wide class gives 42°.
- The cruise-160 boundary is arithmetically sound. Top-wide, with the stub away along `-o.normalized()*200` (as
  `test_sniper.gd:1095` does), reaches the 420 ring after about 752 px. That takes about 2.97 s at 280 and about
  4.86 s at 160, against a 4.5 s budget. The row passes with about 1.3 s spare and the boundary fails by about 0.36 s.
- The WIDE_TURN → APPROACH deviation is labelled [gap] and justified: a charge can end ~900 px out.
- The tests in rows 1, 2, 4, 5, 8 and 11 can each fail on a plausible wrong build.

One blocking problem remains, plus several non-blocking ones.

## Findings

### B1 — BLOCKING: `on_exposed()` disarms a railed Corvette's contact; every level-1 ram is on a rail today

- `level_1_director.gd:341…986`: all 22 `b.ram()` rows carry `.move(...)`. `enemy_path_mover.gd:70-71` calls
  `suspend_ai()`, which arms the profile (`base_enemy.gd:122-123`).
- Epic §2.6.3 (last bullet): "The rail fallback is the profile itself: on a rail it is armed for life". DECISIONS t16
  says the same: "The ARMOR profile stays armed after exposure".
- The plan wires `_expose` → `_ram_brain.on_exposed()`, and `on_exposed()` does "contact disarmed unless in CHARGE"
  (plan line 80-81). A railed brain never ticks, so its phase is still APPROACH. A railed ram stripped by one homing
  volley would therefore stop dealing contact damage for the rest of its rail.
- That is a shipped-behaviour regression in level 1 until t21/t22 move the rams off rails. No test in the plan catches
  it: `test_on_a_rail_the_armor_contact_stays_armed_and_the_brain_is_idle` (`test_ram_corvette.gd:569`) never strips
  the plates.

**Fix:**
- Latch `_suspended = true` in `RamCorvetteBrain.on_suspended()`.
- Make `on_exposed()`, `on_plate_broken()` and any glow or contact write a no-op for the contact and phase while it is
  set. The exposed damage of 60 and shove 0 still come from `_expose`.
- Add a test: on a rail (`suspend_ai()`), `_strip()` → `contact_profile.is_armed()` stays true, a `_knockback_player`
  touch deals 60 and does not shove, and `phase_changed` never fires.

### N1 — NON-BLOCKING: braking 1400 is set for life, so it also tightens the post-charge "swing wide", which the plan's own rejected alternative warns against

- `_apply_config` sets `_ram_mover.braking = cfg.braking` permanently (plan line 102). `enemy_mover.gd:195` applies
  `braking` whenever `|desired| < |current|`.
- That covers the whole CHARGE → WIDE_TURN slow-down from 620 (700) to 280 (340). At 1400 px/s² it takes about 0.24 s
  and ~110 px. At 500 it takes about 0.68 s and ~300 px.
- The "Alternatives rejected" bullet (line 114) rejects raising `acceleration` because it "would also sharpen … the
  wide turn". A permanent `braking` does exactly that for the outbound leg of the turn.

**Fix:**
- Write `mover.braking = config.braking` on entry to LINE_UP, WIND_UP and STAGGER, and `mover.braking = 0.0`
  (= acceleration) on entry to every other phase. This is a field write, which the single-writer gate allows, the same
  as `max_speed`.
- Or keep it permanent and say in the plan and DECISIONS why the tighter swing is acceptable.

### N2 — NON-BLOCKING: the stated worst case for braking is wrong, and the real one has zero margin

- Plan line 51 says the fastest LINE_UP entry is "exposed cruise 340". In fact WIDE_TURN can end on its first tick: it
  ends when the commanded heading is within 30° of the player. The boost-capped case (test 4, the player still ahead
  along `charge_dir`) or a charge that fell short starts the turn already within 30°.
- LINE_UP then begins at the full boost speed, 700 when exposed. 700 / 1400 = 0.50 s = `line_up_cap` exactly. "≤ 30 px/s
  in WIND_UP" still holds, at about 0–23 px/s at the cap tick, but only by coincidence of the numbers.

**Fix:**
- Correct the sentence.
- Add a config-inequality assertion read from fields:
  `(max(charge_speed, exposed_charge_speed) − 30) / braking ≤ line_up_cap`.
- Add a dual case: an exposed, boost-capped charge whose WIDE_TURN exits on its first tick still has speed ≤ 30 on
  every WIND_UP tick.

### N3 — NON-BLOCKING: the attack gate has no tick margin, so a natural LINE_UP can still expire

- `brain.tick` runs `budget.update()` before the phase logic (`ram_corvette_brain.gd:53`). LINE_UP lasts up to
  `line_up_cap`, and float accumulation can add one tick.
- A LINE_UP entered with `remaining()` within a tick of 0.5 can therefore hit expiry on the tick its cap ends. The
  result is DISENGAGE with no charge.
- Epic §2.6.2's table says LINE_UP expiry is "only reachable through a test seam", and t22 relies on that wording. The
  Swarm precedent the task cites guards exactly this case with `ATTACK_GATE_MARGIN := 0.15`, "a few physics ticks of
  rounding" (`swarm_drone_brain.gd:95-96, 249`).

**Fix:** gate on `remaining() >= line_up_cap + ATTACK_GATE_MARGIN`, with a small constant of a couple of ticks. This
still satisfies "LINE_UP only if remaining() ≥ line_up_cap". Add a boundary case: LINE_UP entered with
`remaining() == line_up_cap + margin` always reaches WIND_UP before expiry.

### N4 — NON-BLOCKING: test 10's ≥ 20° guarantee depends on the spawn distance; the plan should pin it and widen it

- The 25° figure holds for a spawn 800 px above the player, which is the level-1 (0, −400) design offset. For a spawn
  500 px above, the same offset gives a ring crossing at about 11° (my derivation: s ≈ 120 along (0.678, 0.735), point
  ≈ (81, −412)).
- As written ("ram spawned exactly above a centred player"), test 10 could be satisfied or failed by the choice of
  distance alone.

**Fix:**
- State that test 10 spawns at the level-1 top offset (800 px above the camera centre).
- In the attack-in-budget runs (test 13), also assert that every first charge is ≥ 20° off vertical. They already
  cover every real spawn class, so this checks R4.35 where it matters at no extra cost.

### N5 — NON-BLOCKING: the Assault APPROACH silently changes the epic's "curved intercept" into a plain seek

- Epic §2.6.2 says "Curved intercept at `cruise_speed` … In Assault the approach target is offset sideways". Plan line
  35 uses `seek(P + offset)` without lead and does not mark it as a [gap].
- It also makes the dual-mode edit (step 4, "zero the offset") a coincidence of the stub being stationary.
  `test_enemy_dual_mode.gd:496` should be a true equivalence.

**Fix:** seek `target.predicted_position(INTERCEPT_LOOKAHEAD) + offset`. With offset 0 this reduces exactly to
`Steering.intercept` (`steering.gd:50-53`), so the dual-mode case stays an identity for any player velocity.

### N6 — NON-BLOCKING: the evasion test should assert direction, not just magnitude

- Test 9 asserts that "the lateral velocity relative to the player's aim line > 0".
- If `side` is mapped with the wrong sign, `Steering.strafe` (`steering.gd:68-72`) jinks the Corvette into the aim
  line. A magnitude check still passes on that build.

**Fix:** assert that the Corvette's perpendicular distance from the player's aim line increases over the 0.5 s, and
that the sign matches the side it started on.

### N7 — NON-BLOCKING: the attack-in-budget harness should run one offset at a time for its assertions

- Corvette bodies are on layer 1, mask 1, by default (`ram_corvette.tscn` root sets no layers), so they body-collide
  with each other.
- In a single all-offsets run, the four top-wide variants (±220/±255/±260/±270, −400) all converge on the same
  `P + (±240, −240)` point and push each other, which skews the measured times.

**Fix:** assert on per-offset runs, at the stub centre and the stub away, the way `test_sniper.gd:1093-1103` does for
the away case. A combined run may still print the per-life charge counts.

### N8 — NON-BLOCKING: smaller gaps to close while implementing

- The "side chosen at APPROACH entry" must also run in `_start()`. The initial APPROACH never goes through
  `enter_phase` (`ram_corvette_brain.gd:42, 80-82`).
- Add a test row for exposure that lands mid-CHARGE: the contact stays armed until the boost ends, then disarms.
- Add a test row for a plate broken during STAGGER: no restart and no second `phase_changed`. The plan states both
  behaviours but tests neither.
- The WIDE_TURN rate assertion is on the commanded `turn_dir`, which is just `Steering.turn_toward`'s output. Keep it,
  since it catches the wrong rate constant. Consider also bounding the time-averaged velocity heading rate once the
  speed has settled at cruise, so the visible arc is checked too.

## Summary

Fix B1 (railed rams must keep their contact armed after exposure, with a test). Then address N1–N3, which are cheap
and concern exactly the timing and feel the task is about. N4–N8 tighten tests that otherwise pass on wrong builds.
After that the plan is ready to implement.

# Review round 2
VERDICT: APPROVED

I reviewed `3-plan.md` (first line "Revision 2") against round 1 and against the code at HEAD `5505090`. I re-read
`ram_corvette_brain.gd`, `ram_corvette.gd`, `ram_corvette.tscn`, `enemy_mover.gd`, `steering.gd`, `engagement_budget.gd`,
`contact_profile.gd`, `armor_plate.gd`, `base_enemy.gd::suspend_ai`, `enemy_path_mover.gd`,
`assault_corridor_constraint.gd`, `swarm_drone_brain.gd`'s gate, `wave_manager.gd`'s spawn position, the ram cases in
`test_ram_corvette.gd` and `test_enemy_dual_mode.gd`, and epic §2.6.2 / §2.6.3 / §2.9.3 / §2.9.4 and the §4 t17 row.

The blocking finding is resolved and so is each non-blocking one. What I checked that the revision could have broken:

- **Rails latch (B1).**
  - `enemy_path_mover.gd:70-71` suspends from the path mover's `_ready()`, before any brain tick.
    `base_enemy.gd:122-125` arms the profile and only then calls `on_suspended()`. A latch set there is in place
    before any `plate_broken` or `armor_broken` can reach the brain.
  - `_expose` (`ram_corvette.gd:136-143`) still writes damage 60 and shove 0 by itself, so a railed, stripped ram
    deals 60 and does not shove. That is the test 8 rail row.
  - Nothing else in the plan disarms the profile. Every disarm goes through `on_exposed()` or a phase entry, and a
    railed brain never ticks.
- **Braking per phase (N1/N2).**
  - `EnemyMover.braking` is an `@export` field with no scene override (`ram_corvette.tscn:196`). `_apply_config` does
    not touch it (`ram_corvette.gd:73-75`), so the un-entered spawn APPROACH (`_start()`) already runs at 0. No
    entry is missing.
  - Every later transition goes through `enter_phase` (`ram_corvette_brain.gd:62`), test seams included. Writing the
    value there covers all seven phases, DISENGAGE among them.
  - `step()` uses `braking` only when `|desired| < |current|` (`enemy_mover.gd:195`). A boost ignores it
    (`:187-188`). The 500 px/s² post-charge slow-down and wide turn are therefore untouched.
  - (700 − 30) / 1600 = 0.42 s ≤ 0.5. In WIND_UP `move_toward` from a velocity of ≤ 30 toward `aim · 20` never
    exceeds max(|current|, |desired|), so "≤ 30 every tick" holds once LINE_UP has ended.
- **Gate margin (N3).** `project.godot` sets no `physics_ticks_per_second`, so the rate is 60 Hz.
  - LINE_UP ends on the tick `_phase_time ≥ 0.5`. Float accumulation can stretch that to 31 ticks (0.517 s).
  - Gate open means `remaining() ≥ 0.55` after that tick's `budget.update`. On the tick LINE_UP ends, at least
    0.033 s is still left, so a natural LINE_UP cannot expire.
  - The acceptance "with `remaining() < line_up_cap` it never enters LINE_UP" holds, because the gate is stricter.
  - Epic §2.6.2 says "entered **only if** `remaining() ≥ line_up_cap`" and "LINE_UP (only reachable through a test
    seam)". Both hold. The margin only tightens the first, and the second is what the margin buys.
  - §2.9.3's deferral (2.1 s) does not include LINE_UP and is unchanged.
  - The attack-in-budget row loses 0.05 s against about 1.3 s of spare time. The cruise-160 boundary fails by more
    than before, not less.
- **Deferral with STAGGER.**
  - Expiry in WIND_UP followed by a stagger defers at most 0.65 + 0.4 s.
  - Expiry in a STAGGER entered from LINE_UP defers at most 0.4 s.
  - Pending always ends in DISENGAGE (plan line 85) and never in a second LINE_UP. Both cases are therefore inside
    the 2.1 s that t22 budgets.
- **Approach identity (N5).** `seek(pos, predicted_position(0.5) + 0, cruise)` is literally `Steering.intercept`
  (`steering.gd:50-53`), so `test_enemy_dual_mode.gd:496` stays an identity.
  - That case starts 501 px from the player and runs 30 ticks from rest, about 62 px of travel. Both modes stay in
    APPROACH (> 420), so the gate's INF-vs-4.5 difference never shows.
- **Test 10's spawn.** The spawn is `cam.global_position + offset · WORLD_SCALE` (`wave_manager.gd:194`), so (0, −400)
  is y = −440 against a 360 centre, as the plan states.
  - The 420 ring crossing at about (180, −379) from P is at y ≈ −19. That is inside the visible rect (y ≥ −380), so
    the corridor has latched `entered` before LINE_UP.

## Findings (all NON-BLOCKING, fix during implementation)

### R2-N1: the corridor's edge pressure is applied after braking, so a WIND_UP outside the visible rect can exceed 30 px/s

- `assault_corridor_constraint.gd:64-74`: once entered, any axis outside `visible` gets up to 200 px/s of inward
  pressure, added after the mover's braking (`enemy_mover.gd:199-200`). Before entry the speed floor is 60
  (`:65`).
- A Corvette that lines up in the soft band, for example after an overshoot near the bottom edge, never meets
  LINE_UP's `speed ≤ crawl_speed` exit, and its WIND_UP speed is not ≤ 30.
- I found no level-1 geometry that does this: the ring crossing and the charge end both lie inside the rect for
  centred players. But the two Assault halves of the dual speed rows (test 2 and the R1-N2 boost-capped case) must
  keep the Corvette inside `inner_rect()` from LINE_UP to CHARGE. The boost-capped run is the risky one: 1015 px of
  boost.
- **Fix:**
  - Place those runs so they stay inside the rect.
  - Assert as a sanity check that the Corvette is inside `inner_rect()` at WIND_UP entry, so a later failure is not
    misread as a braking bug.
  - Note the edge case in the DECISIONS entry.

### R2-N2: the gate-margin boundary (test 10) must run LINE_UP to its cap, or it cannot fail

- If LINE_UP exits early (nose within 8° and slow), WIND_UP starts long before `remaining()` reaches 0, and the case
  passes on a build with `ATTACK_GATE_MARGIN = 0`.
- **Fix:**
  - Drive the cap path the way test 5 does (a stub orbiting faster than the nose turns), and assert that LINE_UP
    ended at the cap.
  - Admit LINE_UP naturally through the gate, not with `enter_phase`. Set the remaining time by writing
    `budget.seconds`.
  - Optionally add a case with `remaining()` in `[line_up_cap, line_up_cap + margin)` that asserts no LINE_UP. This
    pins the margin itself.

### R2-N3: test 9's 0.5 s Open Space window sits close to the engage ring

- The test must start inside `evade_range` (600) and stay outside `engage_range` (420) for 0.5 s. At the exposed cap
  of 340 with the nudge, closing is about 300 px/s radially. A start at cruise just under 600 ends near 450.
- **Fix:**
  - Start the Corvette from rest, so it covers about 60 px.
  - Assert `phase == APPROACH` throughout the window. Entering LINE_UP silently stops evasion and would turn
    "perpendicular distance grows" into a geometry accident.

### R2-N4: glow in LINE_UP is unspecified

- WIDE_TURN can now end on its first tick (the R1-N2 case), while the glow is still about 1.
- The plan sets glow in WIND_UP (ramp from 0), CHARGE (1), WIDE_TURN (fade) and STAGGER (0), but not in LINE_UP or
  APPROACH. The plates would hold the glow through LINE_UP, then snap to 0 when WIND_UP starts.
- **Fix:** LINE_UP and APPROACH continue the fade (or hold 0). Then the glow is at 0 before every WIND_UP ramp, and
  test 2 can assert `glow == 0` at WIND_UP entry.

### R2-N5: per-phase writes need one home

- Plan line 58 ("every other phase's entry writes 0") and the exposed-contact rule ("disarm on leaving CHARGE") are
  both per-entry writes.
- **Fix:** put both in `enter_phase`'s entry code, not in the individual tick functions. The test seam then exercises
  them too, and t19's appended hub phases inherit braking 0 by default.
- A one-line assertion in test 0 or test 2 is enough: after `enter_phase(WIDE_TURN)` the mover's `braking` is 0, and
  after `enter_phase(LINE_UP)` it is `config.braking`.

## Round-1 findings

| Finding | Status | Where in Revision 2 |
|---|---|---|
| B1: exposure disarms a railed ram | **Resolved** | Plan line 88-90 (latch in `on_suspended`, `on_exposed` / `on_plate_broken` inert); test 8 rail row (armed, 60, no shove, no `phase_changed`) |
| N1: permanent braking sharpens the wide turn | **Resolved** | Line 56-59: braking written on LINE_UP / WIND_UP / STAGGER entry, 0 elsewhere; line 127-128 alternative updated |
| N2: wrong worst case, zero margin | **Resolved** | Line 59-63: worst case 700, `braking` 1600 → 0.42 s; config inequality (test 0); dual boost-capped case (test 2). See R2-N1 for placement |
| N3: no tick margin on the gate | **Resolved** | Line 31-35: `ATTACK_GATE_MARGIN` 0.05 (≥ 1 tick at 60 Hz, which is all LINE_UP's cap can overrun); boundary in test 10. See R2-N2 |
| N4: ≥ 20° depends on spawn distance | **Resolved** | Line 48-50; test 10 pinned at 800 px / y = −440 (matches `wave_manager.gd:194`); test 13 asserts ≥ 20° per run |
| N5: plain seek instead of curved intercept | **Resolved** | Line 38-40: `seek(predicted_position(0.5) + offset)` = `Steering.intercept` at offset 0 |
| N6: evasion test checks magnitude only | **Resolved** | Test 9: component away from the aim line > 0, perpendicular distance grows. See R2-N3 |
| N7: Corvettes collide in a combined run | **Resolved** | Test 13: one offset per run, both stub positions |
| N8: spawn side choice, mid-CHARGE exposure, STAGGER re-break, flown heading | **Resolved** | Line 42-43 (lazy `side = 0`), test 7 (mid-CHARGE exposure), test 8 (break in STAGGER), test 6 (flown heading rate) |

## Summary

Revision 2 resolves B1 and N1–N8 against the code. The new mechanisms (rails latch, per-phase braking, the 0.05 s
margin, STAGGER deferral) hold up: they are consistent with epic §2.6.2 / §2.6.3 / §2.9.3 and with the t17 acceptance
rows. The five findings above are test-placement and specification details. Handle them during implementation. None
needs another plan round.
