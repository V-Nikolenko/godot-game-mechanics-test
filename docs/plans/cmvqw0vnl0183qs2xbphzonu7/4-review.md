VERDICT: CHANGES_REQUESTED

Round 1 review of `3-plan.md` (t9: turret groups and the power source). I read the plan, `1-context.md`, the epic plan's "For every task", §2.7, §2.8,
§2.10 and §2.19, `CLAUDE.md`, and the code listed below. I also checked the plan's numbers against the code. The design is sound, follows the epic,
and its claims about the codebase hold. Two test gaps need closing before implementation (B1, B2). Everything else is non-blocking.

## What I verified (no finding)

- **Same-call shutdown is possible as designed.** `base_enemy.gd:242-249` sets `was_killed`, emits `died` and only then calls `queue_free()`, so
  `_on_provider_died` runs inside the lethal `received_damage.emit`. `DefenseTurret.set_powered(false)` (`defense_turret.gd:69-74`) calls
  `brain.power_down()` (`defense_turret_brain.gd:58-67`), which sets the light to OFF and calls `mount.power_down()` on every mount. That reaches
  `BeamTurretMount._stop_weapon()` -> `EnemyBeam.cancel()`, which turns TELEGRAPH into OFF and ACTIVE into FADE (`enemy_beam.gd:188-196`). It also reaches
  `BurstCannonMount._stop_weapon()`, which stops the `BurstClock` and leaves rounds in flight alone. None of this adds anything to physics. The never-reverses rule
  holds: `set_powered(true)` is ignored once off (`defense_turret.gd:70`), and an UNPOWERED mount never leaves that state (`turret_mount.gd:96-97, 134-135`).
- **The stagger seam exists as the plan assumes.** `turret_mount.gd:58` (`telegraph_gate`) and `:245-252` show the gate is asked last, a refusal
  keeps the mount in TRACK, and the mount asks again next tick. `.bind(self)` matches the zero-argument `telegraph_gate.call()`. Row 6's numbers work:
  `request_telegraph` grants on the group clock, the group ticks before the members, so turret 2 is granted exactly 18 ticks (0.3 s) after turret 1,
  and the ring turrets at (−100, 0), (0, 0) and (100, 0) are 150–180 px from G + (0, 150), within `trigger_range` 300 (`pulse_ring_mount.gd:25, 64-65`).
- **The owner group can be read before `add_child`.** `_resolve_owner_group()` reads `owner_group` with `get()` (`defense_turret.gd:119-124`), and the plan sets it in
  `TurretGroup._init()`.
- **World-anchor arithmetic.** `enemy_view_rect()` is centred on `global_position + offset` (`arena_camera.gd:102-104`), and `projectile_world_rect()` is
  centred on the pinned (640, 360) (`:88-89, 116-119`). `EnemyWorld.has_view_rect()` / `has_projectile_world_rect()` exist (`enemy_world.gd:27, 51`).
  `WaveManager._spawn_ship` sets `global_position` *before* `add_child` (`wave_manager.gd:194-209`), so the anchor in `_ready()` is not overwritten.
  The offset it subtracts is the one the spawn used in the same call, camera shake included, so it cancels exactly. Row 2: (640 + 100 − 128) − 100 = 512,
  and the members land at 462 / 512 / 562. The boundary lands at 612.
- **Scoring.** For a non-BaseEnemy with no `died` signal and `counts_toward_wave_clear` / `counts_as_escape` false, `ScoreTracker._on_enemy_spawned`
  (`score_tracker.gd:137-172`) tallies nothing and connects only `tree_exited`, which then returns early (`:220`). Members reach it through
  `EventBus.enemy_spawned_orphan(enemy: Node)` (`event_bus.gd:69`; the `station_reinforcements.gd:258` precedent).
- **Pools resolve to the container.** `bullet_pool.gd:60-63` resolves the container in `_ready()` as the grandparent. The turret builds its pools as root
  children inside its own `_ready()`, so a sibling member's pools resolve to the container.
- **The friendly-fire row cannot pass vacuously.** The ring centre is the mount (Slot0 at (0, 0)), 78.1 px from the source. The band is 24 px wide and grows
  about 6 px per tick, so it overlaps 78 px on about 4 ticks. The two gaps are 180° apart (`energy_ring.gd` `gap_center_deg`), so if the source's
  bearing is outside a gap, the +180° outsider is too. The "band crossed the source outside a gap" assertion is the right non-vacuity check.
- **The shutdown row cannot pass vacuously.** The burst is stopped with 1 ≤ rounds < `burst_count`, so the later "no `round_fired`" check has teeth.
  The TELEGRAPH and ACTIVE beams are both covered.
- **The roster plan matches the gates.** `test_base_enemy.gd:62` `_MIN_ROSTER_SIZE` 14 -> 15, `:285-292` `_AUTHORED_CONTACT_MODES`, the `no_hitbox`
  entries in `test_contact_hitbox_geometry.gd:63-67` and `test_enemy_contact_damage.gd:81-86`, `test_wreck.gd:46`, and the dual-mode template at
  `test_enemy_dual_mode.gd:1095`. `defense_turret.tscn` is a valid template for the source (shared circle, HurtBox 512/65, NONE, no ContactHitBox).
- **The guard row fits.** `test_engagement_deadline.gd:99` `_section_has_scene()` and the existing guard rows (`:420`, `:753`) are the pattern the
  new row follows.
- **No reinvention.** No generic group spawner, coverage helper or power coupling exists anywhere. `Minefield` and `StationReinforcements` are cited correctly as precedents.
- **Gate time.** The plan estimates about 0.6 s against the 1.2 s allotment, which is plausible. The cost is mostly hand-ticked rows. The heaviest is
  600 steps × 3 turrets × 2 harnesses, and UNPOWERED ticks are cheap: `TargetInfo.player` plus a droop. Only rows 1 and 10 wait on real frames. Each
  burst turret builds a pulse pool of about 28 rounds, and there are about 15 such instantiations, so that is a few hundred ms at worst.

## Findings

### B1 (blocking): the coverage row cannot detect a broken distance test
Plan, Test plan row 7, and Design, "Coverage" (`coverage_holes()`: "fewer than `coverage_min` reaches cover (`reach ≥ distance`)"). Both boundaries
remove a whole slot, which drops the mount count to 1 < 2 *whatever the reaches are*. The main assertion also passes whenever every mount counts. So
an implementation that ignores reach, uses the wrong mount position (for example, forgets the slot offset), or compares the wrong way passes all of
row 7. The reach-vs-distance comparison is the coverage rule (epic §2.10.1 R8.11), and nothing checks it.
**Fix:** add a reach-sensitive boundary on `assault_pair` with both turrets present. Raise `coverage_radius` past
`reach_of(PULSE_RING) − |(50, −60)|` (300 − 78.1 = 221.9 px; for example 240). Assert that holes appear on the side away from the ring turret and that the
bearing toward it (about −50°) is *not* a hole. Alternatively, keep 180 and set `coverage_min` 3, which must leave every point a hole. The first version
is better, because it pins the geometry and not just the count.

### B2 (blocking): nothing pins the power source's `counts_as_escape = false`
Plan, `PowerSource` and Elsewhere, against epic §2.19, which requires `counts_as_escape = false` in the `.tres` for the five static kinds. The
`test_base_enemy.gd` sweep (`:213-235`) only checks that the node copies whatever the config says. t6 pinned the turret's value with a real-`ScoreTracker`
drift-out row (epic §2.7 rows). The power source drifts out of Assault with its turrets, so if its `.tres` flips to true, every passed group costs the
player a 0.75× combo, and no gate fails.
**Fix:** add an assertion. Either put `(load(power_source_config.tres) as PowerSourceConfig).counts_as_escape == false` and `source.counts_as_escape ==
false` in the dual-mode case, or better, give `test_turret_group.gd` an Assault drift-out row with a real `ScoreTracker` like t6's. That row can also cover
a whole group drifting out: the combo is unchanged, and the group's own `tree_exited` costs nothing, which also pins "the group is never scored" from the
acceptance criteria.

### N1 (non-blocking): add "dark members stay destructible and still score"
Epic §2.10.1 Power: "Unpowered members stay **dark, harmless and destructible**, still score". Row 4 checks the dark and harmless parts but never the
destructible part. A later change that stops the hurtbox monitoring in `set_powered(false)` would pass every row. At the end of row 4, a lethal
`received_damage.emit` on A must emit `died`. If B2's `ScoreTracker` exists, the score should also rise by A's `score_value`.

### N2 (non-blocking): `rest_bearing_override` has no test and its default clobbers a value
Plan, `DefenseTurret` edits, and `spawn_members()` step 2. This is new behaviour in `defense_turret.gd`, and no row asserts it. Step 2's nesting is
also ambiguous: is the rest bearing applied only when `slot.variant >= 0`? With `TurretGroupSlot.rest_bearing_deg` defaulting to 90.0 and applied
unconditionally, every group slot overrides the member's authored first-slot bearing, even when the preset author never set one. That will matter when t11's
heavy emplacement goes into the hub preset. Two options: default the slot's export to NAN and copy it only when it is not NAN, or state the rule explicitly.
Either way, add one assertion, for example a code-built slot with `rest_bearing_deg` 270 giving `mounts()[0].rest_bearing_deg == 270`.

### N3 (non-blocking): row 10 does not test the anchor through the real spawn path
Test plan row 10 asserts x 512 "(offset 0)". At offset 0 the anchor does nothing, so this row cannot tell whether the anchor runs on the
`WaveManager` path. It is also the only row that uses that path. Row 2 reproduces the formula by hand. The harness player defaults to (0, 0), so the
`ArenaCamera` (`arena_camera.gd` `_physics_process`) will pan once frames run. The offset is therefore not reliably 0, but 512 still holds *because* of the
anchor. Make that deliberate: put the player off-centre in x (for example x 0, so the camera pans toward −100), record `cam.offset.x` from an
`enemy_spawned` handler, assert it is non-zero, and assert the group still lands at 512. Also set the player's y so the members stay above the view
(no rounds), or count the container by type, as the row already says.

### N4 (non-blocking): row 4 says "freed", but the row never runs a frame
Row 4: "the turret killed first stayed dead (freed, never in `members()`)". The row runs entirely hand-ticked with no await, so the killed turret is
`is_queued_for_deletion()` but not freed, and `_on_member_exiting` has not run. Either assert queued and absent from `members()`, or add one `await
process_frame` at the end and then assert it is freed and `member_left` fired for it.

### N5 (non-blocking): make the "B's victim never hit" check provably meaningful
Row 4 places the fixture victim "on B's line" and asserts it is never hit. Add a geometric sanity assertion, as row 8 does: the victim's distance to
B's beam segment (muzzle along `Vector2.RIGHT.rotated(beam.global_rotation)`, out to the beam's length) is at most 14 px. A mis-placed victim would
otherwise make "never hit" pass for the wrong reason.

### N6 (non-blocking): re-seed the shared rng object in row 8
`defense_turret.gd:142` gives each mount `_turret_brain.rng` by reference. "Re-seeded" must mean `brain.rng.seed = S` on that object, not assigning a new
`RandomNumberGenerator` to `brain.rng`. A new object would leave the mount drawing its gap bearing from the old one. Say this in the row, and log the
chosen seed. The non-vacuity assertion will catch a seed that puts the source in a gap, but the implementer should know why it failed.

### N7 (non-blocking): pin the drift-out decision on providers
Design, `_forget_provider` decides that a provider leaving without `died` never darkens the group. The plan explains this reasonably (epic: "on the
last provider's `died`"), but no row pins it. A cheap check: `queue_free()` the source with no lethal hit, wait a frame, and assert `is_powered()`
is still true and the turrets are not UNPOWERED. Record the decision in DECISIONS.md, as the plan already intends for deviations.

### N8 (non-blocking): disconnect the autoload signal
Row 1 connects a handler to `EventBus.enemy_spawned_orphan`. Disconnect it at the end of the row, as `test_station_reinforcements.gd:283-285` does. A
lambda left connected to an autoload outlives the test.

## Summary
The plan solves the task and follows epic §2.10.1–§2.10.4 and §2.19 without contradicting them. Its claims about the code are accurate, and the rows'
geometry and timing work against the real mounts, beams, ring, camera and WaveManager. Two test gaps block approval. B1: the coverage row has no
boundary that depends on reach versus distance, so a coverage check that ignores ranges would pass. B2: nothing pins the power source's
`counts_as_escape = false`, which §2.19 requires. Both fixes are a few lines and fit inside the 1.2 s allotment. N1–N8 are smaller improvements:
dark members still destructible, the rest-bearing plumbing and its default, using row 10 to prove the anchor on the real spawn path, and three
non-vacuity or hygiene fixes.

---

# Round 2 (Revision 2)

VERDICT: APPROVED

I re-read Revision 2 of `3-plan.md` and re-checked the changed parts against the code: the TurretGroupSlot export, `spawn_members()` step 2, rows 4,
7, 8, 10, 11 and 12, and Risks. Both blocking findings are fixed, and N1–N7 are answered in the plan text. Nothing new is blocking.

## Round-1 findings, re-checked

- **B1 (fixed): row 7 now has a boundary that depends on reach.** The ring turret is 78.1 px from the origin. A point at radius 240 is
  within the ring's 300 px only when the angle θ between it and the ring turret's bearing satisfies 240² + 78.1² − 2·240·78.1·cos θ ≤ 300², i.e.
  cos θ ≥ −0.70, θ ≤ 134.6°. The burst cannon (700 px) covers every point, because 240 + 78 = 318. So the holes are exactly the points more than 134.6°
  from the ring bearing (about −50.2°): bearings about 84°–175°, i.e. the nine 10° points from 90° to 170°. All of them have a negative dot product
  with the ring turret's position. The point nearest the ring bearing (310°) is covered by both turrets. All three assertions hold on a correct build,
  and a build that ignores reach, drops the slot offset or inverts the comparison fails them.
- **B2 (fixed): row 11 pins `counts_as_escape = false`.** It uses the t6 set-up (`test_defense_turret.gd:420-444`: `start_tracking()`, `_process` off,
  `_combo` 4.0) and asserts both the shipped `.tres` flag and the live flag. If the source's flag flipped to true, its drift-out would multiply the combo
  by 0.75 (`score_tracker.gd:220-224`), so the row can fail. The group's own announcement goes through `_on_enemy_spawned` with
  `counts_toward_wave_clear` / `counts_as_escape` false and no `died` signal. On `tree_exited`, `enemy.get("was_killed")` returns null on a
  `TurretGroup`, which is not an error, and then the `counts_as_escape` early return fires. So "the group is never scored" is now pinned by
  behaviour, not inferred from flags. The fixture-enemy control matches t6's.
- **N1 (fixed): row 4 checks dark turrets stay destructible and still score.** `_on_enemy_died` adds `floor(score_value · combo)` with combo ≥ 1, so
  "at least `score_value`" is the correct bound.
- **N2 (fixed): the rest bearing defaults to NAN.** The default is now "keep the member's own bearing", step 2 applies each override separately, and row 12
  tests both directions. The NAN-export fallback in Risks is sensible.
- **N3 (fixed): row 10 proves the anchor on the real spawn path.** `ArenaCamera` writes `offset` only in `_physics_process` (`arena_camera.gd:122-146`),
  so switching that off holds `offset` at (−100, 0). The spawn then lands at 640 − 100 − 128 = 412, the anchor moves it back to 512, and the members
  land at 462 / 512 / 562. The group sits at y −80 with the view's y range 0..720, so no member perceives anything and no rounds enter the container.
- **N4 (fixed):** row 4 asserts "queued for deletion" while hand-ticked, then "freed" plus `member_left` after one frame.
- **N5 (fixed):** row 4 checks that the victim lies on B's beam segment.
- **N6 (fixed):** row 8 re-seeds the shared rng object in place, with the seed as a named constant.
- **N7 (fixed):** row 11 checks that a source freed by drifting out, not by dying, leaves the group powered.

## Round-2 findings (all non-blocking)

### R2-1 (non-blocking): place row 11's group so the burst turret is not already below the rect
In `assault_pair` the burst turret sits 60 px *below* the source. If row 11 copies t6's `end_y − 1` placement for the group origin, the burst turret
spawns about 59 px past `projectile_world_rect().end.y`. Any physics frame with that turret's `AssaultDrift` still on frees it at once, including the
frame between the deferred spawn and the hand-tick switch-off, or the frame the row awaits after the source's drift-out. Then the "neither turret is
UNPOWERED" check reads a freed instance. Two ways to avoid it:
- Call `spawn_members()` directly, switch off every member's drift physics before any await, and step each drift by hand.
- Or place the origin at least 61 px above `end.y` and step only the source's drift first.
Say which one the row uses.

### R2-2 (non-blocking): row 1's text does not mention the disconnect
The revision summary says N8 is answered, but row 1 does not mention disconnecting the `EventBus.enemy_spawned_orphan` handler. Rows 4 and 11 connect
a real `ScoreTracker` to the same autoload; it disconnects when freed only if it is autofreed, as t6's is. Add the disconnect to row 1 when writing it,
and `add_child_autofree` the trackers.

### R2-3 (non-blocking): ScoreTracker in row 4
Row 4 starts a real `ScoreTracker` in both harnesses before the spawn. Use t6's `set_process(false)` there too. Otherwise its survival timer and combo
decay run during row 4's final `await` and can award or emit things nothing asserts, which is harmless but noise. The "at least `score_value`" bound
holds either way.

## Gate time
Rows 4 and 11 now each await one or two frames, and rows 10–12 are small. The plan's ~0.7 s estimate still fits the 1.2 s allotment.

## Summary
Revision 2 fixes B1 with a coverage boundary whose geometry I checked (holes at bearings 90°–170°, none near the ring turret), and B2 with a real
ScoreTracker drift-out row that pins the source's `.tres` flag and the group's "never scored" behaviour. N1–N7 are folded into rows 4, 8, 10, 11 and
12, and the new rows work against `arena_camera.gd`, `score_tracker.gd`, `assault_drift.gd` and `wave_manager.gd` as described. What is left is
implementation care: row 11's placement relative to the projectile-rect edge, row 1's handler disconnect, and keeping row 4's tracker's `_process` off.
