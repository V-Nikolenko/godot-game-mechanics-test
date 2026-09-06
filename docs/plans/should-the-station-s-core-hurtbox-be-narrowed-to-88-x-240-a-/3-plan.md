# Station core hurtbox: 88 x 240 or the whole hull?

> **Revision 2** (after `4-review.md` round 1, `VERDICT: CHANGES_REQUESTED`). The design verdict
> is unchanged and the reviewer independently agreed with it. What changed is the *deliverable*:
> the load-bearing premise is now pinned by two real physics tests instead of by prose (blocking
> finding 1), the negative case is an in-memory test instead of a hand-edit-and-revert ritual
> (blocking finding 2), and findings 3-7 are folded in. Corrections to round 1's numbers are
> marked **[R1]**.

## Verdict up front

**No. Do not narrow it.** The core `HurtBox` keeps the body's 240 x 240 `RectangleShape2D`, and
the decision gets pinned by tests and written down where the next reader will find it.

## Problem

Today, a shot anywhere on the station's 256 px hull registers: in phase 1 it deflects (hull
flashes, 0 damage, `armor_deflected` fires); in phase 2 it damages the core. The backlog asks
whether the core `HurtBox` should shrink to an 88-wide central strip so its x-extents
(`[-44, 44]`) stop overlapping the turrets' (`[50, 102]`).

What the player would experience after that change, measured in `1-context.md`:

- While the hull is axis-aligned, `2 x (6 + 26) = 64` px of the boss's 256 px visible width —
  **25 %** — becomes empty air. A shot fired up those lanes hits nothing, plays nothing, and
  reports nothing. Not "deflected": *absent*.
- In **phase 2** it is far worse. `station_turret.gd:73-77` closes each turret's hurtbox on
  death (`monitoring`, `monitorable` and the shape all disabled), so once the armour is gone the
  only damageable thing on the boss is the 88-wide strip: 88/256 = 34 % of the visible width
  left live, **66 % dead — at the exact moment the fight has told the player "the core is open,
  shoot it."**
- And the hull is *rotating* during phase 2 (`station_laser_phase.gd`, `laser_rotation_speed =
  0.5 rad/s`). A strip hurtbox rotates with it, so whether a given lane connects depends on the
  hull's current angle. The player has no way to read that, and it is not a skill the fight
  teaches.

The stated benefit is cosmetic and, on inspection, does not exist. The original argument was
that "a bullet fired up a turret lane triggers a core deflection *before* it reaches the
turret". It does — and then **it still hits the turret for full damage in the same pass**,
because a player bullet is not consumed by the first hurtbox it overlaps (`bullet.gd:84` emits
`expired` without freeing; the only `queue_free()` at `:49` is gated on `range_px > 0.0` and
`assault/scenes/player/weapons/modes/default.tres:12` sets it to `0.0`; `straight_behavior.gd:22`
bypasses `BulletPool` entirely, so nothing on the player path listens to `expired`). So narrowing
buys the removal of one extra hull flash and pays for it with a quarter-to-two-thirds of the boss
becoming untouchable.

**[R1]** The backlog text cites `space_station.tscn:16-17`; the real lines are `:22-23` (the
`sub_resource`), `:71-72` (body) and `:80-81` (core `HurtBox`).

## Design

### The rule this decision states

> **An enemy's `HurtBox` covers the body collider the player collides with.** Armour is a
> *damage rule* on a full-size hurtbox, never an absent hurtbox.

**[R1, finding 5]** Stated precisely, because the test can only assert what it can measure: the
enforced relation is `HurtBox ⊇ body CollisionShape2D`, not `HurtBox ⊇ sprite`. For the station
those differ — a 240 x 240 collider under a 256 x 256 sprite leaves 8 px per edge of visible hull
outside *both* boxes. That pre-existing 8 px lip is out of scope here and is called out in the
new test file's header so nobody mistakes the sweep for an art check.

This is not a new rule; it is the one the codebase already follows and has just paid to enforce
on the other side of the collision pair:

- **11 of 11** assault entities hand their `HurtBox` the body `CollisionShape2D`'s own `Shape2D`
  resource. **[R1, corrected]** They are not all at the same *scale*: measured extents are equal
  for 5 of 11, and the other 6 differ by at most 0.67 px (gunship: body 83.079 px vs hurtbox
  82.405 px; sniper: 40.320 vs 40.616; ally_fighter: 29.405 vs 29.936; drone_interceptor and
  interceptor differ by ~1e-5 px of float noise). **Three of eleven fail a bare
  `Rect2.encloses()`**, so the tolerance below is load-bearing from the first line, not a patch
  applied after a red run.
- Commit `501d662` established that a contact box smaller than the visible ship is a **defect**,
  and `tests/integration/test_contact_hitbox_geometry.gd` is the gate that came out of it.
  Narrowing a hurtbox to 37 % of its hull is the same defect class, chosen on purpose.
- The genre agrees: *"Enemies should have big hitboxes"* (Boghog), and the canonical armoured-core
  boss guards its core with **walls or force fields the player must break through** — objects
  that stop the shot — not with missing collision (Gradius Wiki). See `2-research.md`.

### Alternatives considered and rejected

| Alternative | Why rejected |
|---|---|
| **Narrow the core `HurtBox` to 88 x 240** (the proposal) | Creates 25 % (phase 1) to 66 % (phase 2) dead width on a visibly solid hull, rotating in phase 2. Directly contradicts active epic `boss-fight-escalation-...` task 1, *"Every shot that lands on the station hurts the station."* (`BACKLOG.json:315-322`), which would have to re-widen it as its first act. |
| **Narrow it, and add a separate "armour plate" `HurtBox` over the shoulders** | This is the Gradius idiom done properly and it would work — but it is a new mechanic (a third HP bucket, new art, new destruction feedback) on a boss whose approved epic is about to collapse five HP pools into one. Wrong time, and far more than "one `sub_resource` and one node property". |
| **Keep the shape, but suppress the deflect flash when the shot will also hit a turret** | Requires the core to know a bullet's future trajectory. Not implementable at the hurtbox layer, and it deletes feedback the genre says to keep. |
| **Do nothing at all and close the task** | Loses the answer. This question has already been asked, dropped, and re-raised once; an unattended agent will re-litigate it a third time. The decision has to become code, not prose. |

### The premise this verdict rests on, and why it gets its own tests

**[R1, blocking finding 1]** The verdict's load-bearing fact is *a player bullet crosses the
deflecting core and still hits the turret behind it*. That is true today — but the repo's own
backlog files the same behaviour as **probably a bug**
(`code-health-backlog` / `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`, still
`todo`: *"the player's default shot is effectively infinitely piercing against stacked hurtboxes
... That is probably not intended"*).

If a later cycle "fixes" that so a bullet dies on its first hurtbox overlap, then with a
full-hull core hurtbox **every shot aimed at a turret is absorbed by the core one to two physics
frames early, deflects for 0 and dies — the turrets become unkillable and the boss becomes
unkillable.** A purely geometric sweep would stay green through all of it, because it measures
rectangles.

So the premise gets pinned by physics, not prose. And doing so closes the coverage gap
`ENEMY.md:467-472` has carried since sub-item 2, which asks for exactly this test: *"Closing it
needs a test that instances `assault/scenes/projectiles/bullets/bullet.tscn` and steps physics."*
There is precedent for the technique — `test_station_laser_phase.gd:174-207` already places a
real layer-128 stub `HurtBox` in a beam's path and lets physics find it.

### What actually gets built

The deliverable is not a scene change — it is making "no" durable in the places that keep this
project honest: **two physics tests** on the premise, a **geometry gate** on the conclusion, the
**entity doc**, and the **test docs**.

1. **`tests/integration/test_space_station.gd`** — two new tests that fire a *real*
   `bullet.tscn` through real physics (details in the test plan). These are the ones that make
   the verdict safe, and they close a documented coverage gap.
2. **`tests/integration/test_enemy_hurtbox_geometry.gd`** — a new project-wide invariant sweep,
   the sibling of `test_contact_hitbox_geometry.gd`: every assault entity's `HurtBox` must cover
   its body `CollisionShape2D`. An 88-wide station core fails it by 76 px on each side.
   - Project-wide rather than station-only on purpose: the decision's content is a *rule*, the
     roster already satisfies it 11/11, so pinning it costs nothing today.
   - Geometry compared as entity-local `Rect2`s via `cs.transform * cs.shape.get_rect()` —
     verified working headless on 4.6.3, including the `Transform2D * Rect2` product.
   - **Tolerance 1.0 px** inward per edge. **[R1, finding 7]** The justification is the smallest
     projectile *half-width* in the game: the enemy bullet capsule is `radius = 2.0`
     (`enemy_bullet.tscn:6-7`) and the player bullet is a default-radius-10 capsule under a root
     `scale.x = 0.236342` (`bullet.tscn:13-17`), i.e. 4.73 px wide / 2.36 px half-width. 1 px of
     tolerated slack therefore cannot open a gap a projectile could slip through. (Enemy bullets
     are layer 256 / mask 128 and never test an enemy hurtbox at all, so the player bullet is the
     only projectile this bound has to respect — the enemy figure is the conservative one.)
   - **[R1, finding 6]** It asserts *coverage*, one-sided, and the honest reason is: the defect
     this file exists to catch is **undamageable visible hull**. An oversized hurtbox is the
     opposite defect, nobody has ruled on a tolerance for it, and asserting near-equality today
     would silently forbid a future deliberate widening that no decision has considered. (Round
     1 justified this by pointing at `ally_fighter` and `sniper_enemy`; measured, their surplus
     is 0.27 px and 0.15 px, inside the tolerance, so that was not the real reason.)
3. **`assault/scenes/enemies/space_station/ENEMY.md`** — the collision section records the
   decision, its reasons, the rejected alternatives, **and the load-bearing dependency on the
   not-consumed bullet**, cross-linked to the open backlog item.
4. **`tests/README.md` and `CLAUDE.md`** — both enumerate the suite's invariant tests. The new
   file joins that list, via the `updating-project-docs` skill.
5. **No `.tscn` and no `.gd` production change.** `space_station.tscn` is already correct.

## Build sequence

1. **Premise first.** Add the two physics tests to `tests/integration/test_space_station.gd` and
   run that file alone. Watch the turret-lane test go green, and sanity-check it is not vacuous
   by asserting the turret's HP actually moved by the bullet's 50.
2. Write `tests/integration/test_enemy_hurtbox_geometry.gd` (roster + completeness guard +
   coverage sweep + the in-memory 88 x 240 negative case + the vacuity guard). It must be green
   on the current tree.
3. Confirm the negative case bites: `test_the_88x240_proposal_fails_this_sweep` must fail if the
   coverage predicate is stubbed to `return true`. **[R1, blocking finding 2]** No `.tscn` is
   edited and nothing is reverted — the proposal is applied to the *instance*'s
   `CollisionShape2D.shape` inside the test, which is safe in a loop that auto-commits and
   leaves a permanent gate rather than a paragraph.
4. Update `ENEMY.md`'s collision section with the decision and the dependency note; update its
   "known coverage gap" wording, now partly closed.
5. Run `bash /agent/verify.sh`, then `bash scripts/check-test-leaks.sh` — the new physics tests
   `await`, which is the leak trap `tests/README.md` documents.
6. Invoke `updating-project-docs`; update `tests/README.md` and `CLAUDE.md`.

## Test plan

### A. Premise — real physics, in `tests/integration/test_space_station.gd`

Harness: the file's existing container + `_spawn_station()`. A `bullet.tscn` instance is added to
the **container** (not the station), so it is unaffected by any station transform, and given a
`global_position` in the lane under test. `Bullet._physics_process` moves it at `speed = 900`
along `Vector2.UP.rotated(rotation)`, i.e. 15 px per 60 Hz frame.

| Test | Setup | Asserts | Fails if |
|---|---|---|---|
| `test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core` | Bullet at station-local `(76, 200)`, rotation 0. It crosses the core rect's bottom edge at `y = 120` (~6 frames) and reaches the lower-right turret's rim at `y = 102` (~7 frames). Step 12 physics frames. | The turret's `Health.current_health` dropped by exactly 50; the station's is still 600; `armor_deflected` fired at least once | **the premise breaks.** If bullets ever start dying on first overlap, this goes red and whoever made that change is told, at the point of the change, that the station's turrets just became unkillable. It also proves a player bullet can physically reach both layer-512 hurtboxes — the gap `ENEMY.md:467` records |
| `test_a_real_bullet_damages_the_core_once_the_armor_is_broken` | Kill all four turrets (existing `_kill_all_turrets`-style helper / direct `received_damage`), then bullet at station-local `(0, 200)`, step 12 frames | The station's `Health.current_health` dropped by 50 | the core's `collision_layer`/mask is ever set to something no player bullet can hit — a state every one of the file's nine existing direct-emit tests passes happily |

Both are **intent** tests, consistent with the file's header.

### B. Conclusion — geometry, in `tests/integration/test_enemy_hurtbox_geometry.gd`

Harness copied from `test_contact_hitbox_geometry.gd:84-107` (throwaway `Node2D` container per
entity, `add_child_autofree`, direct children only). Roster of 11 including `ally_fighter`.
Comparison factored into `_covers(body: CollisionShape2D, hurt: CollisionShape2D) -> bool`
returning a bool, so the negative case can call it directly.

| Test | What it asserts | Fails today if... |
|---|---|---|
| `test_every_hurtbox_covers_its_body_hull` | For all 11: the `HurtBox`'s entity-local rect contains the body's, within `_TOLERANCE_PX = 1.0` per edge | any enemy's damageable area shrinks below its body collider |
| `test_the_88x240_proposal_fails_this_sweep` | **The boundary case, as a permanent gate.** Instantiate the station, swap *the instance's* core `CollisionShape2D.shape` for a fresh `RectangleShape2D(88, 240)`, assert `_covers()` returns **false** and that the shortfall is the expected 76 px per side | the sweep is ever loosened into something the actual proposal would pass — which is exactly how a geometry test rots into a rubber stamp |
| `test_the_station_core_hurtbox_spans_the_hull_not_just_the_core` | **[R1, finding 4]** Expressed *relative to the scene*, not as a magic 239: the core hurtbox rect covers the body rect, **and** the body rect's x-extent reaches past the turret span `\|x\| = 102` — so it still means "the core spans the hull" after a legitimate hull resize by epic task 4 | the core stops covering the turret ring, i.e. the shoulders go dead |
| `test_every_enemy_scene_is_in_the_roster` | **[R1, finding 3]** `DirAccess` over `assault/scenes/enemies/`: every `<dir>/<dir>.tscn` appears in `ROSTER`. Precedent: `test_suite_integrity.gd:51`, `test_project_load_integrity.gd:96` | a new enemy is added and silently escapes the sweep — the gap the two *existing* hand-maintained rosters both have |
| `test_every_roster_entry_has_exactly_one_hurtbox_with_one_shape` | Structural precondition for the sweep | a hurtbox is deleted, or given a second `CollisionShape2D` the sweep would silently ignore |
| `test_the_roster_contains_a_scaled_hurtbox_or_this_file_is_vacuous` | At least one entry has a non-identity hurtbox transform | the transform composition stops being exercised and the sweep degrades to comparing raw `Shape2D`s — the vacuity `test_contact_hitbox_geometry.gd:168-183` guards against |

## Risks

| Risk | Check |
|---|---|
| The physics test is timing-fragile (bullet overshoots or under-travels) | 12 frames gives 180 px of travel against a 98 px gap, and the turret rim spans `y ∈ [50, 102]` — a 52 px window, 3.5 frames wide. Margins on both sides. If flaky, assert on `Health` rather than on frame counts and raise the frame budget |
| The bullet leaks (it never `queue_free()`s itself — that is the premise) | Parented to the test's `add_child_autofree` container, so it dies with the container. `scripts/check-test-leaks.sh` is in the build sequence |
| `Shape2D.get_rect()` / `Transform2D * Rect2` unavailable or wrong in 4.6.3 | Verified headless twice, independently, by author and reviewer |
| A rotated `CollisionShape2D` would make the rect an AABB, not the shape | No roster entity rotates its collision shapes, and the sweep instantiates them at rest before `station_laser_phase` can spin anything. Noted in the file header |
| The 1 px tolerance quietly grows into a real gap | Named constant with the projectile half-width justification in a comment |
| Instantiating 11 scenes leaks | The sibling file already instantiates the same 11 with the same harness and the gate is green |

## Out of scope

- Any change to `space_station.tscn`, `space_station.gd` or the armour rule.
- The shared-HP-pool rework — that is `boss-fight-escalation-...` task 1, and it is the reason
  this decision leans the way it does, not something to start here.
- **Deciding** whether the infinitely-piercing player bullet is a bug. This plan pins the current
  behaviour and makes the consequence for the station loud; the balance question stays its own
  open backlog item.
- `ram_ship`'s hurtbox **mask** (33, excluding the player bullet's layer 64). Reachability bug
  with its own backlog task; this sweep is geometry only and says nothing about masks.
- Extracting the two *existing* hand-maintained rosters into a shared helper. The new file gets a
  completeness guard; retrofitting the other two is a separate cleanup.
- The 8 px lip between the 240 collider and the 256 sprite, and the sub-pixel scale deltas on six
  scenes.
