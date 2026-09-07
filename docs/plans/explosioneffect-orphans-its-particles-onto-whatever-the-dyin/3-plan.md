# ExplosionEffect — own the particles instead of guessing where they go

> **Revision 2** — rewritten after review round 1 (`4-review.md`). Changes: added component
> change 0 (position-before-parent, the reviewer's R1), rebuilt the site enumeration (R2),
> corrected the turret rationale (R2c), added the non-identity-container tests that can actually
> fail on R1 (R3), added the `test_damage_reaction.gd` leak fix (R4), and added the mandatory
> docs step (R5).

## Problem

**What the player sees today**, three separate visible faults from one component:

1. Six of the game's AI racers — `bogomol`, `booster_gold`, `pacer`, `isac`, `fang`, `reacher` —
   die with **no explosion at all**. They simply vanish.
2. A racer eliminated by a track hazard blasts at the **top-left corner of the world** instead
   of at the wreck.
3. **Race walls and race asteroids explode 777 px up-track**, and a destroyed station turret
   blasts roughly a screen away from itself — because the particles' world coordinate is applied
   as a *local* one.

`1-context.md` has headless proof of all three. The common cause is that
`global/components/explosion_effect.gd` decides *where its particles go* by a fixed two-hop node
walk (`:40,43`) and *when to set their position* before they have a parent (`:51-55` vs `:70`).
The first silently encodes a placement rule no call site can see; the second is only ever correct
because most containers happen to be at identity.

**What should change:** an entity that dies explodes **where it died**, in every container,
including moving and offset ones. The component stops depending on a placement rule its callers
cannot see, and where a caller genuinely needs the FX somewhere specific it says so in the call.

## Design

Four changes to `global/components/explosion_effect.gd`, then two call sites.

### Change 0 — set the position *after* parenting (the biggest visible fix)

`:51-55` assigns `p.global_position` while `p` is still out of the tree. A parentless `Node2D`
has no parent `CanvasItem`, so `global_position` is just `position`: the intended world
coordinate is stored as a local one, and `container.add_child(p)` at `:70` then applies the
container's transform on top.

Move the position assignment to **after** `container.add_child(p)`. It is safe: the assignment is
synchronous within the same call, before any frame is processed, so the pre-set `emitting = true`
(`:58`) cannot produce a one-frame flash at the wrong place.

This is the fix for defect 3, and it is the reason the turret change below matters for *look*
rather than only for hygiene.

### Change 1 — resolve the actor by walking up, not by one fixed hop

```gdscript
var actor := _nearest_node2d()   # was: get_parent() as Node2D
```

Walk from `get_parent()` upward to the first `Node2D` ancestor. This is what fixes the racers:
`DamageReaction` is `extends Node` (`damage_reaction.gd:4`), so the current single-hop cast
yields `null` and `explode()` returns at `:41-42`. Walking up finds the ship one hop further.

**It changes nothing at any site that works today** — each of those has a `Node2D` parent, found
on the walk's first hop. Verified row by row against the corrected ten-site table in
`1-context.md`, `station_death_sequence.gd:179` included (its parent is `_station`, a
`CharacterBody2D`).

The obvious cheaper alternative — read the effect's own `global_position` instead of walking —
**does not work**: under a plain `Node` parent the `CanvasItem` chain is broken and the effect's
`global_position` reads `(0, 0)`. Confirmed by probe in review round 1. So the walk is not
over-engineering.

Critically, this fixes `DamageReaction` **without moving the `ExplosionEffect` node**, so
`tests/unit/test_damage_reaction.gd:38` (`the death explosion is owned by the DamageReaction`,
which iterates `_dr.get_children()` at `:41-44`) stays green. Moving the node would have been the
obvious alternative and would have broken that test.

### Change 2 — an explicit `container` argument, which is what the backlog item asked for

```gdscript
func explode(at: Variant = null, container: Node = null) -> void:
```

An explicit container wins; `null`, or a node that is not inside the tree, falls back to today's
default of `actor.get_parent()`. Appending an optional parameter leaves all other call sites
untouched.

### Change 3 — fail loudly, not silently

The `as Node2D` early return is the mechanism that hid defect 1 for the entire life of the
component. Replace it with a `push_warning` naming the effect's path before returning. Research
finding 5 (groups are rejected precisely because they "result in silent faults") and finding 4
point the same way: the expensive failures here are the quiet ones. Fires per death, not per
frame, so it is exempt from the `OS.is_stdout_verbose()` convention.

### Call-site fixes

| File | Change | Why |
|---|---|---|
| `assault/scenes/race/core/race_ship.gd:97-100` | `add_child(boom)` instead of `get_parent().add_child(boom)`; drop the now-dead `boom.global_position = global_position` | Makes the ship the actor, so the blast lands on the wreck. `explode()` never reads the effect's own transform, which is why that line did nothing. `apply_lethal_hazard()` is driven from `HazardSystem` during physics, not from `tree_exiting`, so the `add_child` is legal. |
| `assault/scenes/enemies/space_station/station_turret.gd:79-81` | pass the station's container explicitly, with a null guard falling back to the default | **Accurate reason:** the FX currently sit *inside the hull* — so they inherit the station's translation and rotation (visibly wrong once change 0 lands the coordinate correctly) and are **freed with the wreck** mid-burst. It is *not* a production iteration bug: `space_station.gd:137-143` already filters `child as StationTurret` and the gunnery goes through `_station.turrets()`; the `$Turrets` incident in `tests/README.md:558-566` was in a test helper. |
| `global/components/damage_reaction.gd` | **no change** | Fixed entirely by change 1. |

For the turret, use `get_parent().get_parent() as SpaceStation` then its parent — the same node as
`owner` (probe-confirmed that `owner` *is* the `SpaceStation` for turrets authored in
`space_station.tscn`) but without depending on scene-authoring metadata, which an
editable-children override could change. Guard both a null station and a null parent; on either,
pass `null` and take the default.

### Alternatives rejected

- **A group-based FX host** (`get_tree().get_nodes_in_group("fx_layer")`). Rejected on research
  finding 5: a mistyped group name returns an empty array with no error, reproducing the exact
  silent-failure class this task exists to delete.
- **A dedicated `Effects` layer node in every level scene.** Architecturally the right end state
  (research finding 4), and it would also stop FX inflating `level_director.gd:131`'s
  `container.get_child_count() > 0` poll, which currently holds a section open until every death
  blast self-frees. **Deferred deliberately:** it changes `ENEMIES_CLEARED` timing, which
  `test_level_1_sequence.gd` pins, and it needs wiring in three level scenes plus a defined
  fallback when a level author forgets it. That is a second change, not this one. Noted for the
  report.
- **Reparenting the existing child effect at death time** (the common forum answer). Rejected on
  research finding 2: reparenting from `tree_exiting` errors with *"Parent node is busy setting
  up children"* and needs `call_deferred`. Spawning a fresh, already-detached node — what the
  component does now — sidesteps that entirely and is worth keeping.
- **Pooling the particle nodes.** Rejected on research finding 3: `finished` only fires while
  `one_shot` is true, so a pooling mistake converts every explosion into a silent permanent leak.

## Build sequence

1. **`tests/unit/test_explosion_effect.gd`** — the component's first test file. Write it against
   current behaviour first and watch the three defect tests fail (non-`Node2D` parent,
   transformed container, loud warning).
2. Component change 0 (position after parenting) — the transformed-container test goes green.
3. Component changes 1 and 3 (ancestor walk, loud failure) — the remaining unit tests go green.
4. Component change 2 (`container` argument) + its unit tests.
5. Fix `tests/unit/test_damage_reaction.gd`'s `_build()` to interpose a container `Node2D`
   (see risks — change 1 makes it start leaking particles into the test script).
6. `race_ship.gd` call-site fix.
7. `station_turret.gd` call-site fix.
8. **`tests/integration/test_explosion_effect_placement.gd`** — the invariant test over real
   entity death paths.
9. Gate: `bash /agent/verify.sh`, then `scripts/check-test-leaks.sh`.
10. **Docs** (mandatory per `CLAUDE.md`): invoke `updating-project-docs`. The old two-hop rule is
    restated in ~12 places that all become wrong — listed under "Docs to update" below.

## Test plan

### `tests/unit/test_explosion_effect.gd` (new)

- `test_particles_are_not_children_of_the_effect` — they must go to the container, or they die
  with the entity. The premise of the whole component.
- `test_particles_land_in_the_actors_parent_by_default` — pins today's default.
- `test_particles_spawn_at_the_actor_position` — identity container.
- **`test_particles_land_at_the_actor_position_under_a_transformed_container`** — *fails before
  change 0.* Actor under a container `Node2D` with a non-zero `position` **and** a rotation,
  asserting the particle's **`global_position`** equals the actor's. The boundary case for the
  component's core promise, and the case every identity-container fixture hides.
- **`test_an_effect_under_a_non_node2d_parent_still_explodes`** — *fails before change 1.* Builds
  the `DamageReaction` shape: `Node2D` ship → plain `Node` → `ExplosionEffect`. Asserts a
  `CPUParticles2D` exists and sits at the **ship's** position.
- `test_an_explicit_container_overrides_the_default`.
- `test_an_explicit_container_still_uses_the_actor_position` — `container` re-homes the blast, it
  does not move it; `at` is the thing that moves it. Uses a **transformed** explicit container,
  so it also guards change 0.
- `test_the_at_argument_overrides_the_position_but_not_the_container` — pins the existing
  `StationDeathSequence` contract.
- `test_a_null_or_detached_explicit_container_falls_back_to_the_default` — the fallback must not
  be a crash or a no-op.
- **Boundary — `test_an_effect_with_no_node2d_ancestor_warns_and_does_not_crash`**: effect under a
  bare `Node` tree with no `Node2D` anywhere above. Asserts the warning with GUT's
  `assert_push_warning()` (`addons/gut/test.gd:2416`), not merely the absence of particles —
  absence is also what the broken build produces, so without the warning assertion the test name
  is a promise the assertions do not keep.
- `test_the_particles_free_themselves_when_finished` — guards research finding 3. Set a short
  `lifetime` on the effect first and `await` longer than it, so the suite does not pay 0.5 s.

### `tests/integration/test_explosion_effect_placement.gd` (new, invariant)

Real entity scenes, real death paths, asserting the blast is **present** and **in the right
place** — the class of check that would have caught all three defects:

- **Roster is a directory sweep**, not a hand list: every `*.tscn` under
  `assault/scenes/race/racers/` whose scene state carries a `DamageReaction` node. Following
  `test_config_instance_isolation.gd`'s roster style, a seventh racer is covered the day it
  lands. Each is instantiated, damaged to death, and must produce a `CPUParticles2D` within 1 px
  of where the racer died. (Instantiating racers headless works; expect a benign
  `[RaceParticipant] No RaceDirector in group 'race_director'` warning from
  `race_participant.gd:41` — `_exit_tree` at `:107-109` null-guards the unregister, so freeing
  them is safe.)
- **`test_a_race_wall_under_the_real_track_offset_explodes_at_the_wall`** — a real `RaceWall`
  under a `Track` node at `position = Vector2(0, -777)`, the real authored offset from
  `race_level_1.tscn:79-80`. Asserts the blast is at the wall. This is the site the first version
  of the context table wrongly marked "OK", and it fails on today's build.
- `test_a_hazard_eliminated_racer_explodes_at_the_wreck` — calls the real
  `RaceShip.apply_lethal_hazard()` and asserts the particles are at the ship's position, **not**
  at the origin.
- `test_a_destroyed_turret_leaves_its_blast_outside_the_hull` — kills a real `StationTurret` on a
  real `SpaceStation` positioned **away from the origin**, and asserts the particles are at the
  turret's world position and are not descendants of the station (so they survive the wreck).
- `test_a_dying_enemy_still_explodes_into_its_container` — a real `BaseEnemy`, proving the change
  is additive for the sites that already worked.

All entities are parented through a container `Node2D` owned by `add_child_autofree`, per
`tests/README.md:551-557`, so the FX do not leak into the test script.

## Risks

| Risk | Check |
|---|---|
| Change 0 breaks a site that is correct today | Only possible if a site *relies* on the offset. None can — the offset is never intentional. `test_a_dying_enemy_still_explodes_into_its_container` plus the whole station family in the gate prove the identity-container sites are unchanged. |
| The ancestor walk changes a site that works today | All ten sites enumerated in the corrected `1-context.md` table; each has a `Node2D` parent found on hop 1. |
| **Change 1 makes `test_damage_reaction.gd` leak into the GUT test script** | Real and expected. `_build()` (`:14-27`) does `add_child_autofree(_host)`, so the host's parent *is* the test script; after the walk, `container` becomes the test script and `:80`/`:92` each leave a `CPUParticles2D` → `GUT WARNING: Test script has 2 unfreed children` (`addons/gut/gut.gd:390`). Build step 5 interposes a container `Node2D` per the README rule. |
| Turret FX moving to `enemy_container` delays `ENEMIES_CLEARED` | **`test_level_1_sequence.gd:141-142` kills all four turrets** before the core, so four extra children land in `_container` — which the same test asserts is empty at `:172` and which gates `_wait_enemies_cleared` (`level_director.gd:131`). They should be gone long before (lifetime 0.5 s, then two more sections, against the `< 10 s` budget asserted at `:168`), and the station's own blast chain already lands there. **If the gate reds, look here first.** |
| Racers suddenly having explosions changes race feel | Purely visual — particles carry no collision and are not in `race_hazards`. `apply_lethal_hazard()` already freed the ship. |
| New FX where there were none leak in other existing tests | Run `scripts/check-test-leaks.sh` after the gate, not just `verify.sh`. |

## Docs to update (build step 10)

- `global/components/explosion_effect.gd:5-6` and the `:34-38` NOTE — the entire "one hop too
  deep" rule this change deletes.
- `assault/scenes/enemies/space_station/station_death_sequence.gd:167-175` — already cites
  `explosion_effect.gd:28`/`:31`, which are `:40`/`:43` today.
- `assault/scenes/enemies/space_station/space_station.tscn:147-149` — "resolves its container as
  `get_parent().get_parent()`".
- `tests/README.md:551-566` — both bullets; the `$Turrets` one becomes false after the turret fix.
- Header comments restating the old rule: `tests/integration/test_space_station.gd:32`,
  `test_station_laser_phase.gd:37`, `test_station_reinforcements.gd:27`,
  `test_station_gunnery.gd:20` and `:58`, `test_station_death_sequence.gd:9`,
  `test_config_instance_isolation.gd:43`, `test_enemy_contact_damage.gd:38`.
- `docs/architecture/modules/global.md` component entry + `CLAUDE.md` if the conventions list
  references the rule.

## Out of scope

- The dedicated per-level `Effects` layer (rejected above, deferred with reasons).
- Changing `level_director.gd`'s `get_child_count()` poll.
- `HitEffect` — `hit_effect.gd:21-38` keeps its particles as its own child and only `restart()`s
  them, so it never outlives its host and has no ownership problem.
- Any change to the particle look: amount, lifetime, colour, velocity all stay as they are.
