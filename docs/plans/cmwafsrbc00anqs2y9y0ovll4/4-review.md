## Round 1

VERDICT: CHANGES_REQUESTED

The design matches epic §2.8. Its one deviation, the `first_launch_delay` stagger in Open Space, fills a detail §2.8 leaves open, stays compatible with
the §2.14 hub row (0.6 + 3.0 + 0.8 s < 0.6 + 0.8 + 9 s) and is logged. It reuses the `LaserTender.launch_pair()` shape, `SquadController`,
`EnemyModule.set_vulnerable()` and `StateLight`, and keeps the conventions (brain rng, flat `String` payloads, signals declared with arity, spawning
from the brain's physics tick). I checked the plan's code claims and they hold, except where a finding below says otherwise. Three test rows cannot
work as written or can pass without testing anything, and a few rows that could regress are missing. All of it is detail, so this asks for changes
and does not reject the plan.

### Required

1. **H2's "consumed in OPEN" shot can hit a child, not the hangar.** I checked `carrier.tscn:262-283` (HangarPort at (60, −56), 64 × 56 hurtbox),
   `swarm_drone.tscn:21` (body radius 13) and `test_carrier.gd:40,168-197` (`_shoot` starts `SHOT` = 110 px out, so it starts at hull x 170 on the line
   y −56). The plan puts the port mouth at hull (108, −56) and spaces the two children ±14 px along the hull axis, at (108, −70) and (108, −42). Each one's
   13 px body is 1 px from the bullet's line. On real physics at 16× with carrier physics on, a shot fired early in OPEN (3.8 s to about 4.3 s, before the
   0.4 s, 300 px/s boost has carried the children past x 228) is consumed by a swarm drone. The hangar's HP stays the same and the row fails, or it passes
   by luck depending on the shot time. Fix it in the plan with one of these:
   - pin the shot times: CLOSED-before ≤ 2.5 s, OPENING ≈ 3.4 s, OPEN ≥ 4.6 s, CLOSED-after ≈ 6.2 s (before the starboard launch at 7.8 s). Add a
     precondition that at fire time no child lies within 40 px of the shot segment.
   - or set `launch_count = 0` on that carrier's private config. `_may_launch` reads room, not count, so the door cycle still runs and no child can
     block the line.

2. **"Live" children must drop queued-for-deletion nodes, and H3 must say how it frees two children.** The plan's `children_of(id)` / `live_count()`
   are "live only" with no definition (3-plan.md:52, :66). H3 frees two port children at 30 s inside a synchronous hand-ticked loop. A `queue_free()`
   there never completes, so an `is_instance_valid` count still sees 3, the port never reopens, and the row fails. An implementer would then be tempted
   to add an await in the middle of the loop. The precedent, `laser_tender.gd:165-169` (`_prune`), drops `is_queued_for_deletion()` nodes. Write that
   rule into `CarrierHangars`: live = `is_instance_valid(c) and not c.is_queued_for_deletion()`, pruned on every read. Then state in H3 whether the
   row calls `free()` or `queue_free()`.

3. **H7's ring row can pass without the ring ever reaching a child.** "A pulse ring started by the carrier over its children leaves their health
   unchanged" stays green if the ring never started, never expanded past the children, or the children sat outside `max_radius`. In W6
   (`test_carrier.gd:1126-1164`) the same claim has a precondition (`started`) and a control (outsiders hurt, `assert_gte(hit, 2)`). Add both here:
   - assert the ring reached EXPANDING and then FADE, with every child inside `ring_export().max_radius`. Children are not ticked, so they stay at the
     mouth, about 110–125 px from the centre.
   - add a non-owner-group `_victim` fixture next to the children and assert it is hurt.

### Should fix (missing regression rows and setup that is not specified)

4. **Emergency deployment mid-OPENING (Assault).** The plan says deployment fires "from whatever door state it is in", then OPEN. A plausible bug is to
   leave the bay in OPENING, or keep its door clock running, so OPENING's own LAUNCH fires 0.8 s later and an Assault hangar launches twice. No row
   catches that. Add H6(d): Assault, core exposed at about 3.4 s while the port is in OPENING. The port deploys once (`launches` 1) and never launches
   again in the crossing.

5. **H6(c) and H4(b) leave out assertions the epic asks for.**
   - H6(c): also assert that the starboard bay, after its emergency deployment at 5.0 s, does not open at 7.0 s (`launches` 1 at the end of the
     crossing). "Nothing from an already-launched Assault hangar" has to hold for both bays.
   - H4(b): epic §2.8 attaches "the carrier keeps fighting" to "destroy both". At the moment the plan asserts it only in (a). Assert phase SCREEN and the
     missile bank fired in (b) too.

6. **Multi-carrier Open Space placement is not specified (H3, H4, H6).** "The still player 775 px off their port side (no movement, no turn)" holds for
   one carrier per world. With three carriers sharing the one harness player (`enemy_ai_harness.gd`: one fake player), placing them in a line puts
   some outside the 600–950 band, so they `arrive` and turn (`carrier_brain.gd:_tick_screen` / `desired_nose`). Specify the placement: on a 775 px
   circle round the player, each spawned with `rotation` = the bearing to the player, so port (local +x) faces it and `desired_nose` asks for no turn,
   and every carrier ≥ 340 px from the player. That keeps every ring off, which matters because a ring hurts enemies outside its owner group
   (`test_carrier.gd:1126` W6), and another carrier's children are outside it.

7. **Clock comparisons.** `_clock >= due` and `door clock >= door_open_seconds` sum 1/60 steps in floating point, so a boundary can land one tick late
   (48 × 1/60 can come out at 0.7999…). `carrier_brain.gd` already has `CLOCK_EPS` (1e-6, the project clock rule). Compare with it so 3.0 / 3.8 / 7.0 /
   12.0 s fall on their exact ticks. H3's "OPENING starts ≥ `launch_period` apart" then needs a ±1-tick tolerance or tick counts.

8. **H4(c) light.** After a mid-OPENING destroy the module turns its `Light` OFF (`enemy_module.gd`, `destroy()`). Assert it is still OFF at the end of
   the 40 s loop. That proves the dead bay never sets CHARGING again.

### Checked and fine (no change needed)

- **Outward boost straight after `add_child` vs §2.8's "on its first tick".** Equivalent. `EnemyMover.boost()` replaces the requests for its duration
  (`enemy_mover.gd:115-118`, `step()` 221-223). Neither payload brain calls `boost()` or `halt()` before attacking: the swarm drone only in BURST
  (`swarm_drone_brain.gd:439`), the fighter brain never. `BaseEnemy` halts only on `suspend_ai` / EMP (`base_enemy.gd:147-160`).
- **Squad and seed set before `add_child`.** Required, because `SwarmDrone._ready()` / `Fighter._ready()` join the squad there (`swarm_drone.gd:31-41`,
  `fighter.gd:40-49`) and `EnemyBrain._ready()` seeds `rng` (`enemy_brain.gd:56-60`). The plan's spawn order does this.
- **PANIC path.** `tick()` → `enter_phase(PANIC)` → `_on_panic_entered()` (guarded by `_panic_applied`) → `_emergency_deploy()`
  (`carrier_brain.gd:110-112, 518-530`). That is the physics step, not a physics callback, and it runs once.
- **Assault timing in the harness.** View y is 0..720, and the projectile rect is y −444..1164 (`arena_camera.gd`, `_visible_rect().grow(64)`). A carrier
  spawned at y 60 is freed at about 13.8 s and leaves the view at about 7.3 s. The starboard launch at 7.8 s needs only the latched clock.
- **Existing `test_carrier.gd` rows.** I traced every row that ticks an engaged carrier for more than 3 s: W1 20 s, W2 / W3, the band, leash and PANIC
  rows, the crossing row's "panic then no engine" carrier (which now deploys its starboard bay on tick 1), W6 (it breaks out of its loop before the
  3.8 s launch), and the free-below row (never in view, so it never launches). None of their assertions reads the container, the enemy count or a
  hangar's vulnerability, so they should stay green. The plan's fallback (a large `first_launch_delay` on that row's private config) is acceptable if
  one does not.
- **Gate time.** The loops come to about 16k carrier ticks in total. The t7 row in `tests/README.md` measured test_carrier.gd going from 1.3 to 3.0 s
  once the four mounts were ticked, so these loops are plausibly inside 2.2 s and well inside the 1.5× escalation line.
- **H2 is Open Space only, though the epic row is unmarked.** Acceptable: the vulnerability window is mode-agnostic module state, and H1 checks it in
  both harnesses. Add one line to DECISIONS.

### Planner response to round 1
All eight findings taken into `3-plan.md`: (1) H2 runs with `launch_count` 0 on its private config (doors still cycle, no child on the line);
(2) "live" defined as valid and not queued for deletion, H3 frees with `queue_free()`; (3) H7 asserts the ring's radius passed every child and adds an
outside-group control victim; (4) new H6(d): core exposed mid-OPENING in Assault → one launch only; (5) H6(c) asserts the starboard never reopens,
H4(b) asserts it keeps fighting; (6) Open Space placement spelled out (775 px circle, port to the player); (7) `CLOCK_EPS` on every clock comparison;
(8) H4(c) asserts the wreck's light stays OFF.

## Round 2

VERDICT: CHANGES_REQUESTED

I checked the revised `3-plan.md` against the code again. Seven of the eight round-1 findings are fixed correctly. Finding 3 (H7's ring row) is only
half fixed: the row can still pass without the ring ever reaching some of the children. That is a one-line change to the row; the rest is ready.

### Required

1. **H7: the ring's gaps can cover the children, so "health unchanged" can pass without the band ever touching them.** I checked
   `energy_ring.gd`, `carrier_pulse_ring.tscn` and `carrier.tscn`:
   - **How the gaps sit.** `EnergyRing.start()` with no argument puts the first gap at bearing 0° (`energy_ring.gd:98-101`). There are two gaps of 50°
     (`carrier_pulse_ring.tscn`), turning at +30°/s from `start()` (`gap_spin_deg`, `energy_ring.gd:54`). The 1.0 s telegraph counts toward that turn.
   - **Where they are when the band arrives.** The band reaches the mouth radius (about 120–125 px) at clock ≈ 1.0 + 125/360 ≈ 1.35 s. The gaps are then
     centred at about 40° and 220°, covering about 15–65° and 195–245°.
   - **What that means in Assault.** The carrier is at rotation 0, so the starboard mouth is at hull (−108, −56) and its two children (±14 px) are at
     bearings ≈ 201° and 213°. Both are inside the second gap. `_scan()` skips a target in a gap (`energy_ring.gd:222`) right after the owner-group
     exemption check, so if the exemption were broken those children would still be untouched and the row would stay green. The port children
     (≈ −33° and −21°) are clear only by chance. In Open Space each carrier's rotation decides it.
   - **The control is open to the same problem.** "A control victim outside the owner group at the same range" has no bearing. If it lands in a gap it
     is not hurt and the row fails for a reason that has nothing to do with the exemption.

   Fix: either
   - call `ring.start(gap_start_deg)` with an angle the row computes so that, at the tick the band reaches each child's radius, no child bearing and no
     control bearing is in a gap,
   - or, simpler, place one control victim co-located with each child (outside the owner group) and assert each control is hurt. A control in a gap
     then fails loudly instead of hiding a vacuous child.

   Either way, also assert `not ring.in_gap(bearing)` for every child and control at the tick the band crosses its distance, as a precondition.

### Verified fixed

- **(1) H2.** With `launch_count` 0 on the private config, `min(launch_count, _room)` = 0 at LAUNCH while `_may_launch` still reads room, so the doors
  cycle (OPENING 3.0 s, OPEN 3.8–5.8 s) and nothing can sit on the shot line.
- **(2) Live children.** "Live" is now `is_instance_valid(child) and not child.is_queued_for_deletion()`, the `laser_tender.gd:165-169` rule, so H3's
  `queue_free()` at 30 s takes effect inside the synchronous loop. The H3 timeline I re-derived holds: port launches 2 at 3.8 s and 1 at 12.8 s;
  starboard 2 at 7.8 s and 1 at 16.8 s; the port is blocked at 21.0 s with due kept; it opens on the tick after 30 s with room min(2, 2) and launches 2
  at 30.8 s; the starboard stays at its cap.
- **(4) H6(d).** Exposing the core at 3.4 s with the port OPENING: deployment launches the port once and moves it to OPEN; the row asserts no second
  launch at 3.8 s and `launches` 1.
- **(5)** H6(c) asserts the starboard never reopens at 7.0 s, and H4(b) asserts the carrier keeps fighting.
- **(6) Placement.** Rotation = the angle of the carrier→player vector `b` makes `Vector2.DOWN.rotated(rotation)` equal `b.rotated(PI/2)`, which is
  exactly `desired_nose()`'s port choice with zero error (`carrier_brain.gd`, `desired_nose`). So no carrier turns. At 775 px every carrier is in the
  band and outside the 340 px pulse trigger, and three carriers on the circle are 1342 px apart. A leftover sentence a few lines later in the test-plan
  preamble repeats the old single-carrier wording; it is harmless, but delete it.
- **(7) Clock.** Every comparison uses `x >= limit - CLOCK_EPS`. `CLOCK_EPS` is a `CarrierBrain` const, so `CarrierHangars` has to reference
  `CarrierBrain.CLOCK_EPS` or declare its own; either is fine.
- **(8) H4(c).** The row now asserts the wreck's light stays OFF on every later tick.

No new problems found in the revised sections.

### Planner response to round 2
H7: one outside-group control victim beside each child (same bearing from the hull centre, 20 px further out), each asserted hurt, so a child in a
ring gap fails the row through its control. The leftover one-carrier placement sentence is deleted. `CarrierHangars` declares its own `CLOCK_EPS`.

## Round 2 — fix check

VERDICT: APPROVED

**My round-2 finding is resolved.** `3-plan.md:140-144` now puts an outside-group control victim beside each child (same bearing, 20 px further out),
asserts each control is hurt, and asserts `not ring.in_gap(bearing)` for every child at the tick the band reaches it. A child sitting in a ring gap can
no longer pass the row quietly. Its control is in the same gap, about 0.06 s and 1.7° of spin later, so the row fails. The leftover one-carrier
placement sentence is gone (`3-plan.md:111-116`), and `CarrierHangars` declares its own `CLOCK_EPS`.

**One thing the fix introduces, which the implementer must handle.** The failure is loud, not silent, so this does not block approval. The row still
calls `ring.start()` with no angle, which puts the first gap at 0°. With the 1.0 s telegraph and the +30°/s spin, the gaps cover about 15–65° and
195–245° when the band reaches the mouths (about 120–125 px). The starboard children land inside a gap in both harnesses:
- Assault (rotation 0): hull (−108, −56 ± 14), bearings ≈ 201–213°.
- Open Space, the carrier at bearing 0° on the 775 px circle (rotation 180°): ≈ 20–34°.

The port children are clear in both (≈ 327–339° and ≈ 146–159°). So any H7 world with starboard children is red by construction: the `in_gap`
assertion and the controls fail.

**Implementation note (binding):** call `ring.start(gap_start_deg)` with an angle the row computes. Every child's and control's bearing at band arrival
(bearing − `gap_spin_deg` × (`telegraph_seconds` + d / `ring_speed`), all read from the scene) should sit at least `gap_deg` / 2 + 10° away from
`gap_start_deg` and `gap_start_deg` + 180°. Do not drop the starboard children to make the row pass.
