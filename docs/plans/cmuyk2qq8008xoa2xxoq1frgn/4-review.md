## Review round 1

VERDICT: CHANGES_REQUESTED

The plan matches the epic's §2.6.1, §2.6.3, ram row of §2.7 and t16 row of §4. B2 and N10 are handled
correctly, and the geometry and the deferred-exposure reasoning hold up when checked against the code
(details under "Checked and holds"). One defect blocks approval: the contact shove the plan wires up
can never fire with the scene as specified, and no test row would catch that. The fix is small.

### BLOCKING

**1. The ARMOR shove is dead: the `ContactHitBox` mask stays 0, and row 11 cannot detect it.**
- `assault/scenes/enemies/ram_corvette/ram_corvette.tscn:102-104` (HEAD): `ContactHitBox` has `collision_layer = 256`,
  `collision_mask = 0`. The in-progress tree on disk still has `collision_mask = 0` next to `shove_speed = 260.0`.
- `global/components/contact_profile.gd:72` connects `_hit_box.area_entered` → `_on_contact` (`:124`), which is the
  only path to `contact_made` and `_shove` (`:139`). With mask 0 the hitbox monitors nothing, so `area_entered`
  never fires. Contact *damage* still lands, because the player's HurtBox (mask 1281) detects the hitbox from its
  own side. But `contact_made` and the shove never happen.
- The modes that rely on `_on_contact` author mask 128: `razor_drone.tscn:106` and `swarm_drone.tscn:89`. t5's
  ARMOR shove test is green only because `tests/helpers/contact_fixture.gd:33` builds its hitbox with
  `collision_mask = PLAYER_HURTBOX`. The real Corvette scene does not.
- The plan's "Design" table gives only "layer 256, CONTACT" for `ContactHitBox`. Its Problem section claims
  "Touching an armoured Corvette hurts (50) and shoves the player away", and the task requires "shove applied
  while armoured only". Test row 11 checks only the damage the player takes and the *field* `shove_speed == 0`
  after exposure. Both pass on a mask-0 build, so the row cannot fail on the defect it should guard.
- **Required:**
  - The scene table sets `ContactHitBox.collision_mask = 128` (`PLAYER_HURTBOX`).
  - Row 11 becomes end-to-end in both harnesses:
    - A player stub that overlaps the real Corvette and exposes `apply_knockback(v)` gets **exactly one** call.
      The impulse has length 260 ± ε, points from the hull centre to the stub, and `contact_made` fires.
    - After exposure, a fresh touch makes **no** `apply_knockback` call and deals 60.
  - State in the plan that this row fails on a mask-0 scene. Run it once against mask 0 to prove that.

### NON-BLOCKING

**2. Engine boost row: use a fresh module per phase.** `global/ship_modules/engine_boost_module.gd:28`
`_hit_this_boost` keeps every enemy already hit and is cleared only on activate or end (`:63`, `:119`). If one
instance calls `_damage_nearby_enemies` for the armoured phase and again for the exposed phase, the second call
skips the Corvette. The test then reads "boost does nothing when exposed" for the wrong reason. Use a new
`EngineBoostModule` per phase, or clear the array between phases.

**3. Nothing pins the mirror side.** Row 3 fires only from the ship's left (+x). N10's assertion uses `|x|`
on the AABB. Neither would catch a sign error that puts `PlateRight` on top of `PlateLeft`, and the homing
volley still strips three plates in that case. Row 12 ("below-left → the nearer side plate") catches it only
indirectly. Either add the mirrored warhead row (from −x, only `PlateRight` breaks) or assert
`PlateLeft.position.x > 0 > PlateRight.position.x`.

**4. N10 bound is a bare literal.** "|x| > 23" is 16 (the inline offset in
`warhead_missile_shooting_state.gd:54`) plus 7 (the capsule radius in `warhead_missile.tscn:43-45`). Read the radius
from the warhead scene's `CapsuleShape2D` and name 16 as the `_launch_warhead` offset in the assertion message, so a
retuned rocket fails with a reason rather than a magic number. Row 7's real volley remains the behavioural proof.

**5. Station case 16 no longer discriminates for this class of ship.**
- `tests/integration/test_station_reinforcements.gd:408-431` asserts `mask & 64 != 0`. The Corvette now passes that
  (1121) while its hull still deflects every primary shot until rockets strip three plates.
- The comment-only change is what the task asks for. But the `station_reinforcements.gd:187-191` comment must
  keep the reason in its new form: "the hull deflects primary fire while armoured". Do not just delete the old
  mask-33 reasoning.
- Optional: strengthen the guard with `not (ship.has_method("is_armored") and ship.is_armored())` at spawn.

**6. Docs made actively false by this task.**
- `docs/architecture/modules/global.md:271-279` says `apply_alternate()` is "exactly the ram ship's" rule and that
  `ram_ship.tscn` authors a mask-33 profile.
- `docs/enemy-roster.md:129-140` still says "Bullet-proof until hit by a missile, then 100 HP" and lists
  `movement_speed`, which this task removes.
- The epic gives the full doc pass to t23. Still, the Bomber task (commit `1f150aa`) touched
  `enemy-roster.md` and `assault.md` in the same commit, and CLAUDE.md's "keep the docs current" is mandatory.
  Fix these two paragraphs now, alongside the `defense_profile.gd` / `base_enemy.gd` comment edits the plan
  already makes.

**7. `test_base_enemy.gd` floor.** Once `ram_corvette` leaves the flip-boundary skip list,
`tests/integration/test_base_enemy.gd:328` `_MIN_ROSTER_SIZE - 2` should become `- 1`. Otherwise the floor
silently loosens by one.

**8. Implementation details the plan should state.**
- `homing_point()` must skip plates that are freed or broken-but-not-yet-freed: `is_instance_valid(p) and p.is_alive()`.
  The fixture at `tests/helpers/armored_homing_fixture.gd:9-12` shows the pattern.
- `_expose()` should guard on `_armored` so `armor_broken` fires once even if two plates break in one step.
- In row 6, autofree the `RocketState` and the out-of-tree `MovementController` stub. `scripts/check-test-leaks.sh`
  catches an orphaned `Node`.

**9. Process note (not a plan defect).** The working tree already holds t16 implementation:
`ram_corvette.gd`, `.tscn`, the config files, a new `ram_corvette_brain.gd`, and the `station_reinforcements` comment,
all uncommitted. This happened before the plan was approved. Finding 1 is already reproduced there.

### Checked and holds

- **B2** (`global/components/armor_plate.gd:117-136`): `_resolve` decides each HitBox once, records the decision
  in `_decisions`, and returns the recorded answer to the second caller. The first caller applies the damage. A
  broken plate records `false` (consumes nothing). So a homing rocket arriving in the same step as the rocket that
  breaks a plate passes on.
- **N10 arithmetic.** `(0,36).rotated(-100°) = (35.45, -6.25)` is correct. The side capsule's shape-rect AABB
  half-width is 14·sin10° + 6·cos10° = 8.34, so the inner edge is at 27.1 px (the true capsule edge is 28.06).
  Rockets reach 16 + 7 = 23 px, so the margin holds.
- **Frontal volley.** The front capsule spans x ∈ [−18, 18], so all three warheads touch it. Plate contact
  (centre ≤ 48.4) comes before hull contact (≤ 37.8) even at x = 16.
- **Rear and side warheads.** A rear rocket on the axis (x ∈ [−7, 7]) crosses the deflecting hull, never touches
  a side plate, and meets `PlateFront` from inside. A side rocket at y = −6.25 meets the side plate (x ≈ 48.4)
  before the hull (≤ 40.5), and its y-span [−13.25, 0.75] misses the front plate.
- **Homing volley.** With only the Corvette in `enemies`, all three rockets lock it. They steer at
  `homing_point` every tick with no turn limit, so each eventually reaches a live plate, and each plate consumes
  exactly one rocket (100 dmg ≥ 50 HP). Three rockets therefore strip three plates whatever the tie-break. Rockets
  two and three stay inside the hull while re-aiming, so no new hull `area_entered` fires.
- **Deferred exposure / double count.** The plate's `broken` is emitted from the physics query flush. Godot then
  runs `SceneTree::physics_process`, which flushes the message queue (`_expose`) and the delete queue (the consumed
  rocket) before the next step's queries. So the hull sees a deflection in the breaking step, and an exposed state
  with no stale rocket in the next one. Row 5 fails on an immediate-flip design.
- **Beam.** `beam_behavior.gd:58-83`: the Corvette body is layer 1, inside the ray mask `1|1024`. While
  `is_laser_blocking()` is true it becomes `blocker_collider` and is excluded from targets, so it takes 0. Once
  exposed, the ray ignores it, and as a member of `enemies` it is burnt through the root `HurtBox`.
- **Hurtbox geometry gate.** `test_enemy_hurtbox_geometry.gd:133` looks only at direct children, so plates under
  `Plates` are invisible to it. The root `HurtBox` shares the r 34 shape and covers it.
- **Sprite transparency.** `ram_ship.png` is 67.19 % opaque (`test_entity_sprite_transparency.gd:30`). The plates'
  `Sprite` nodes carry no texture, and `_register` (`:174`) skips null.
- **Rails.** Every level-1 `b.ram()` has `.move()` (`level_1_director.gd`). Removing `_physics_process`,
  `_check_off_screen` and `movement_speed` changes nothing there. `suspend_ai()` re-arms ARMOR harmlessly.
- **Ship modules.**
  - EMP still skips the Corvette: `_IMMUNE_CLASSES` is unchanged and matches by global name.
  - Dash, nova and shield-overload are direct emitters on the root `HurtBox`, so the hull rule deflects them.
    That matches C2.
  - `fighter_brain.gd:1534` `_mates()` filters `enemies` by squad, so the Corvette joining `enemies` does not
    affect it.

## Review round 2

VERDICT: APPROVED

Revision 2 applies every round-1 finding, and the draft in the working tree matches the plan. I checked each one
against the code, not against the response table.

### Round-1 findings, re-checked

- **1 (was BLOCKING): fixed.**
  - `ram_corvette.tscn:102-104`: `ContactHitBox` has `collision_mask = 128`.
  - `ram_corvette.gd` `_apply_config` sets `contact_profile.shove_speed = cfg.armor_shove_speed`, and `_expose()`
    zeroes it.
  - `test_ram_corvette.gd::test_armoured_contact_hurts_and_shoves_the_player_and_never_the_corvette` builds a real
    player `HurtBox` (layer 128, mask 1281) on a root that records `apply_knockback`. It asserts 50 damage,
    `contact_made` == 1, exactly one impulse of length 260 pointing away from the hull, and the Corvette unhurt.
  - `test_exposed_contact_hurts_more_and_no_longer_shoves` asserts 60 damage and no impulse.
  - Both run in the `open_space` and `assault` harnesses. Mask 0 kills `ContactProfile._on_contact`
    (`contact_profile.gd:72`), so the armoured row fails on mask 0, as the coordinator reports measuring.
- **2: fixed.** `test_engine_boost_is_deflected_while_armoured_and_lands_once_exposed` uses a second
  `EngineBoostModule` for the exposed phase. `ShipModuleBase` extends `RefCounted`, so neither instance leaks.
- **3: fixed.**
  - `test_a_rocket_from_the_other_side_breaks_only_that_side_plate` flies +x at `PlateRight`'s y and asserts only
    `PlateRight` breaks.
  - The N10 test asserts `PlateLeft.position.x > 0` and `PlateRight.position.x < 0`.
- **4: fixed.**
  - The reach is `WARHEAD_OUTER_OFFSET_X` (16) plus the radius read from `warhead_missile.tscn`'s `HitBox`
    `CapsuleShape2D`, sanity-asserted at 23.
  - The inner edge is the minimum |x| over the four corners of the transformed shape rect: plate × hurtbox ×
    collision-shape transforms. That gives the 27.1 px figure.
- **5: fixed.** `station_reinforcements.gd` keeps the "not `ram_corvette`" reason in its new form: the hull
  deflects until rockets break all three plates. Case 16 is comment-only and labelled a generic guard.
- **6: fixed.**
  - `global.md` now says `apply_alternate()` has no shipped user, and that armour is never a narrowed mask.
  - `enemy-roster.md`'s `ram` entry describes the plates, the 120 HP hull, contact 50/60 with the shove, and the
    flat config fields. The squad-table note is restated.
- **7: fixed.** `test_base_enemy.gd`:
  - `_MIN_ROSTER_SIZE - 1`.
  - Ram removed from the flip list and its skip.
  - Mask constants and three ram cases removed.
  - `ram_corvette` kept in `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW` with the reason rewritten.
  - `_AUTHORED_CONTACT_MODES` gains `ram_corvette: ARMOR`.
  - Still no static `RamCorvette` reference.
- **8: fixed.**
  - `homing_point` and `live_plate_count` skip a plate unless `is_instance_valid(plate) and plate.is_alive()`.
  - `_on_plate_broken` defers `_expose` only while `_armored`.
  - `_expose` returns early if already exposed.
  - `_rocket_state` parents the actor and the state under the autofreed harness root, and `autofree`s the
    `MovementController` stub.

### Also checked in round 2

- **Row 5 (`test_exposure_lands_one_step_after_the_last_plate_breaks`).** It breaks the last plate through
  its classifier, then emits `received_damage(100)` on the hull in the same synchronous block. It asserts HP 120,
  then exposure one physics frame later, and that a further 30 lands. An immediate-flip implementation fails it.
- **Row 7 (frontal volley).** It asserts at 45 frames that exactly one of the three real rockets is consumed and
  both side plates are at full HP. Headless runs never fire `screen_exited` (see the note in
  `test_player_bullet_lifetime.gd`), so a rocket that misses cannot count as consumed.
- **Row 6 (homing volley).** It asserts every rocket's `locked_target` is the Corvette, all three plates broken,
  all three rockets spent, hull at 120, and exposure. `RAM_POS` (640, 300) is inside `homing_missile`'s arena
  bounds, so no rocket can count as spent by leaving them.
- **Rows 8–9 (Sniper Shot and beam).** These now catch the `ram_ships` rule coming back, a wrong
  `is_laser_blocking`, and the Corvette missing from `enemies`.
- **`test_player_bullet_lifetime.gd` plate rows.**
  - A bullet launched through `StraightBehavior` that crosses `PlateFront` keeps `MAX_PIERCE` and is not
    consumed.
  - At an exposed hull the bullet is consumed and deals 50.
  - The `unlimited_pierce` row now asserts the Corvette no longer stops the shot and its `HitBox` damage is not
    zeroed.

### NON-BLOCKING

- **Row 13 (rails) is a weak check.** It calls `ram._physics_process` directly after `suspend_ai()` and asserts
  zero velocity. It does fail if suspension stops gating the brain: in the Assault harness the brain would
  intercept the player at (80, 80). But it does not check that `on_suspended()` ran. That is acceptable at this
  task's scope, since t17 adds the light states.
- **Not yet run.** Before committing, run the full gate (`/agent/verify.sh`) and `scripts/check-test-leaks.sh`
  over the whole suite, not just `test_ram_corvette.gd`. This task edits several gate files and adds
  `await`-heavy rows; I did not run them.
