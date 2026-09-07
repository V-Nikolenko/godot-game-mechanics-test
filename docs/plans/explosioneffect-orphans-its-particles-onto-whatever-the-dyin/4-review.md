# Review — ExplosionEffect particle ownership

VERDICT: CHANGES_REQUESTED

The direction is right and most of the plan survives scrutiny: the two headline defects are real
(I reproduced both against the real component), the ancestor walk is the correct minimal fix for
`DamageReaction`, the rejected alternatives are rejected on grounds the research actually
supports, and nothing here reinvents an existing `global/components/` facility. But the plan's
central factual artefact — `1-context.md`'s ten-site table with its "Verdict" column — is wrong
at three rows and missing one site, and as a result the plan leaves the *dominant* cause of
"explosion in the wrong place" unfixed while adding a test suite that would be green with that
defect live. Five required changes below; none is large.

Everything below was checked by reading the named file/line, and the four claims marked
**[probe]** were reproduced with `godot --headless -s` against the real scenes.

---

## Required changes

### R1 (blocking). The component sets the particle position *before* it parents it, so every blast is offset by the container's transform. The plan does not fix this, and it is the real cause of the turret and race-hazard misplacement.

`global/components/explosion_effect.gd:51-55` assigns `p.global_position` while `p` is still
**out of the tree**. For a `Node2D` with no parent, `global_position` is just `position`
(`CanvasItem::get_parent_item()` returns null), so the intended *world* coordinate is stored as a
*local* one. Only at `:70` does `container.add_child(p)` run, at which point the effective world
position becomes `container.global_transform * intended_position`. Every site in the project is
correct today only because its container happens to be at identity.

Two containers in the project are **not** at identity, and both blasts are visibly wrong today:

- **[probe] `station_turret.gd:79-81`.** Real `space_station.tscn` instantiated, station moved to
  `(640, 200)`, `Turrets/Turret0` at world `(564, 124)`. The particles landed at world
  **`(1204, 324)`** — `station.position + turret.global_position`, i.e. a turret blast fires off
  in empty space roughly a screen away. `1-context.md`'s table records only "FX land in
  `$Turrets`" for this row; the position error is the more player-visible half and is unmentioned
  anywhere in the three documents.
- **[probe] `race_wall.gd:24`, table verdict "OK".** Real `race_wall.tscn` under
  `Track` (`race_level_1.tscn:79-80`, `position = Vector2(0, -777)`) → `RaceTrack`, wall at world
  `(320, -4977)`. Particles landed at **`(320, -5754)`** — 777 px up-track. The same applies to
  `asteroid_base.gd:35` for `AsteroidTest1` (`race_level_1.tscn:132-133`), also marked "OK",
  since `RaceAsteroid extends AsteroidBase` and sits under the same `Track/RaceTrack`.

Consequences for the plan as written:

1. The stated goal — *"an entity that dies explodes where it died"* — is not met. After this
   plan, race walls and race asteroids still explode 777 px away and drift further as the track
   scrolls.
2. The turret fix "works" only by accident: it re-homes the FX to the enemy container, which is
   at identity (`level_1.tscn:22`, `level_2.tscn:13`, `race_level_1.tscn:77` — all bare
   `Node2D`, no transform). The plan attributes the fix to `$Turrets` iteration hygiene, which is
   not the live bug (see R2c).
3. The proposed unit test `test_particles_spawn_at_the_actor_position` and the integration
   assertion "within 1 px of where the racer died" will both be **green with the defect
   present**, because every fixture container the plan describes is at identity. A test plan that
   cannot fail on the biggest instance of the bug it is chartered against is the failure mode
   this review is meant to catch.

The fix is one line: move the `global_position` assignment (`:51-55`) to *after*
`container.add_child(p)` (`:70`). It is safe — the assignment happens synchronously in the same
call, before any frame processes, so the pre-set `emitting = true` (`:58`) cannot produce a
one-frame flash at the wrong spot. Add it to the design as component change 0, and add the
non-identity-container cases in R3.

### R2 (blocking). The construction-site table is not a reliable enumeration, and the plan's "checked individually against all ten sites" rests on it.

Verified each row against the source:

| Row in `1-context.md` | What the code says | Table verdict |
|---|---|---|
| `base_enemy.gd:54` (`add_child` at `:55`) | parent = enemy | OK ✔ |
| `player_fighter.gd:46` (`:55`) | parent = player | OK ✔ |
| `ally_fighter.gd:50` (`:51`) | parent = ally | OK ✔ |
| `asteroid_base.gd:35` (`:36`) | parent = asteroid | OK ✘ — see R1, wrong position under `Track` |
| `race_wall.gd:24` (`:25`) | parent = wall | OK ✘ — see R1, off by `(0, -777)` |
| `player_ship.gd:71` (open_space, `:77`) | parent = ship | OK ✔ |
| `space_station.gd` "via base_enemy" | **not a construction site** — it is `base_enemy.gd:54`, already row 1 | duplicate |
| `station_turret.gd:79` | parent = turret | incomplete — position is also wrong |
| `damage_reaction.gd:24` | parent = the `Node` | ✔ confirmed **[probe]**: `world kids=1 ship kids=1 dr kids=1`, no particles anywhere |
| `race_ship.gd:97` | parent = `Racers` | ✔ |

**Missing entirely: `station_death_sequence.gd:179`** (`_fx = ExplosionEffect.new()`,
`_station.add_child(_fx)` at `:181`, fired up to `_blast_count` times from `:196`). That is a
real eleventh `ExplosionEffect.new()` and the site with the most delicate contract in the
codebase — it is the only caller that passes `at`. It is *fine* under the ancestor walk (parent
is `_station`, a `CharacterBody2D`, found on hop 1), but the plan claims to have checked all
sites and this one was never looked at. Note also that its 15-line comment at `:167-175` cites
`explosion_effect.gd:28` and `:31`; the real lines are `:40` and `:43`, so that comment is
already stale before this change lands.

Rebuild the table with the duplicate removed, `station_death_sequence.gd:179` added, and the
three verdicts corrected.

**R2c.** The turret rationale in the plan's call-site table — *"Keeps `CPUParticles2D` out of
`$Turrets`, which `SpaceStation._turrets()` and the gunnery iterate"* — overstates the live
defect. `space_station.gd:137-143` already filters (`var t := child as StationTurret; if t != null
...`), and `station_gunnery.gd:153-158` goes through `_station.turrets()`, so neither can trip on
a particle. The incident `tests/README.md:558-566` describes was in a *test helper*, not
production. Keep the change — with R1 it is still the right call — but state the accurate reason
(the FX are inside a rotating, translated hull, so they render in the wrong place and are freed
with the wreck), or the plan justifies a change with a bug that does not exist.

### R3 (blocking). No proposed test can fail on R1. Add a non-identity container case.

Every fixture the test plan describes puts the entity under a container at identity, which is
exactly the condition that hides R1. Required additions:

- Unit: `test_particles_land_at_the_actor_position_under_a_transformed_container` — actor under a
  container `Node2D` with a non-zero `position` (and ideally a rotation), asserting the particle's
  **`global_position`** equals the actor's. This is the boundary case for the component's core
  promise and fails on today's build.
- Integration: kill a real `RaceWall` (or `RaceAsteroid`) under a `Track` node at
  `position = Vector2(0, -777)` — the real authored offset from `race_level_1.tscn:79-80` — and
  assert the blast is at the wall. This is the site the current table wrongly marks "OK".

Two smaller test-plan notes (non-blocking, but fix while editing):

- `test_an_effect_with_no_node2d_ancestor_warns_and_does_not_crash` **is** assertable: GUT ships
  `assert_push_warning(text, msg)` at `addons/gut/test.gd:2416` and
  `assert_push_warning_count()` at `:2405`. Use them — otherwise the test only asserts "no
  particles", which is also what the broken build does, and the word "warns" in the name is a
  promise the assertions do not keep.
- `test_the_particles_free_themselves_when_finished` needs an explicit `await` longer than
  `lifetime` (default 0.5 s, `explosion_effect.gd:14`); set a short `lifetime` on the effect
  first so the suite does not pay half a second per run.

### R4 (blocking, small). The ancestor walk makes `test_damage_reaction.gd` start leaking children into the GUT test script. The plan checked the wrong thing.

The plan's claim about `tests/unit/test_damage_reaction.gd:38` is **correct** — I verified it: no
node moves, and `test_setup_adds_an_explosion_effect_child` iterates `_dr.get_children()`
(`:41-44`), so it stays green. But the check stopped one step short. `_build()` at `:14-27`
parents the host with `add_child_autofree(_host)`, so the host's parent **is the test script
node**. After change 1, `actor` resolves to `_host` and `container` becomes
`_host.get_parent()` — the test script. `test_death_emits_died_and_frees_the_host` (`:80`) and
`test_overkill_still_dies_once` (`:92`) will therefore each leave one `CPUParticles2D` behind
(they live ~0.5-1 s; the tests return in 2 frames), producing
`GUT WARNING: Test script has 2 unfreed children` from `addons/gut/gut.gd:390` — the exact
message `tests/README.md:551-557` documents.

It is a warning, not a failure, so the gate stays green — but it is noise the project has an
explicit rule against. Interpose a container `Node2D` in `_build()` per the README rule and say
so in the plan.

### R5 (blocking per `CLAUDE.md`). The build sequence ends at "Gate" with no docs step, and this change invalidates a lot of prose.

`CLAUDE.md` makes `updating-project-docs` mandatory after a structural change, and `explode()`
gains a parameter and changes its resolution contract. At minimum these become wrong or stale:

- `global/components/explosion_effect.gd:5-6` and the `:34-38` NOTE (the entire "one hop too
  deep" rule this change deletes).
- `assault/scenes/enemies/space_station/station_death_sequence.gd:167-175` (already citing
  `:28`/`:31`, which are `:40`/`:43` today).
- `assault/scenes/enemies/space_station/space_station.tscn:147-149` ("resolves its container as
  `get_parent().get_parent()`").
- `tests/README.md:551-566` — both bullets; the `$Turrets` one becomes false after the turret fix.
- Header comments that restate the old rule: `tests/integration/test_space_station.gd:32`,
  `test_station_laser_phase.gd:37`, `test_station_reinforcements.gd:27`,
  `test_station_gunnery.gd:20` and `:58`, `test_station_death_sequence.gd:9`,
  `test_config_instance_isolation.gd:43`, `test_enemy_contact_damage.gd:38`.

Add step 8 (docs) to the build sequence and list these.

---

## Checked and confirmed — no change needed

- **`owner` really is the `SpaceStation`. [probe]** Instantiating
  `assault/scenes/enemies/space_station/space_station.tscn` and reading
  `Turrets/Turret0.owner` prints `SpaceStation:<CharacterBody2D#…>`, and `owner as Node2D` is
  non-null. `Turret0`-`Turret3` are declared in that scene's node list (`:95-106`) as
  sub-scene instances, so the outer scene root owns them. No level scene re-declares them
  (`level_1.tscn`, `level_2.tscn`, `race_level_1.tscn` do not mention `Turret*`), so no
  editable-children override is in play. The plan's `(owner as Node2D).get_parent()` resolves to
  the enemy container as claimed. *(Style only: `get_parent().get_parent() as SpaceStation` is
  the same node with no dependency on scene-authoring metadata. Either is acceptable; keep the
  null guard the risk table already promises, and extend it to a null `get_parent()`.)*
- **Defect 1 is real, on a real racer. [probe]** A real `pacer.tscn` under a `Racers` `Node2D`,
  killed with `Health.decrease(99999)`: the ship is freed and `Racers` is left with **zero**
  children. All six racers carry `[node name="DamageReaction" type="Node" parent="."]`
  (`bogomol:50`, `fang:49`, `booster_gold:193`, `isac:49`, `pacer:48`, `reacher:50`), and
  `damage_reaction.gd:4` is `extends Node`, so `explosion_effect.gd:40`'s cast yields null and
  `:41-42` returns. The directory-sweep roster in the integration test will find exactly these six.
- **The ancestor walk resolves the ship. [probe]** Walking up from `fx.get_parent()` in the
  `Node2D → Node → ExplosionEffect` shape returns the ship at `(700, 500)`.
- **The "just use the effect's own `global_position`" shortcut is genuinely unavailable. [probe]**
  Under a plain `Node` parent the effect's `global_position` reads `(0, 0)` — the `CanvasItem`
  chain is broken by the non-`CanvasItem` parent — versus `(700, 500)` as a direct `Node2D`
  child. So the walk is not over-engineering; the obvious one-liner really is wrong.
- **`race_ship.gd:97-100` fix is positionally sound.** `Racers` (`race_level_1.tscn:283`) is a
  bare `Node2D` at identity under the level root, so after `add_child(boom)` the particles land
  at the wreck. Dropping `boom.global_position = global_position` (`:99`) is correct — `explode()`
  never reads the effect's transform. `apply_lethal_hazard()` is driven from `HazardSystem`
  during physics, not from `tree_exiting`, so the `add_child` is legal.
- **No reinvention.** Nothing proposed duplicates `HitEffect`, `HitBox.matching_shape()`, or any
  other `global/components/` facility, and the plan is right to leave `hit_effect.gd` alone:
  `:21-34` keeps its `CPUParticles2D` as its own child and only `restart()`s it (`:38`), so it has
  no ownership problem.
- **No `CLAUDE.md` conventions are contradicted.** The fix stays in the component (composition),
  touches no `.tres` stats, and introduces no design-unit coordinates (FX are world-space). The
  `push_warning` fires per death, not per frame, so it is correctly exempt from the
  `OS.is_stdout_verbose()` rule — though note `station_death_sequence.gd:196` can fire `explode()`
  up to `_blast_count` times per death, so a mis-parented sequence would warn ~7 times, not once.
  Still not per-frame.
- **The research supports the claims it is cited for.** Finding 3's `one_shot` caveat matches
  `explosion_effect.gd:59` and `hit_effect.gd:23`; finding 5 is a fair basis for killing the
  group lookup; finding 2 is a fair basis for keeping the fresh-detached-node design. The
  tradeoff column is populated on all five rows and the judgement call about
  `level_director.gd:131` is explicitly flagged as uncited. Deferring the per-level `Effects`
  layer is the right call and is argued, not hand-waved.
- **`level_director.gd:131`** is quoted accurately (`while container.get_child_count() > 0:`).
- **Scope is finishable in one session** — two component edits plus one line for R1, two call
  sites, two test files. Instantiating racers headless works (a benign
  `[RaceParticipant] No RaceDirector in group 'race_director'` warning from
  `race_participant.gd:41`; `_exit_tree` at `:107-109` null-guards the unregister, so freeing them
  is safe).

## One risk the plan under-states

`tests/integration/test_level_1_sequence.gd:141-142` kills **all four turrets** before the core.
After the turret change those four blasts land in `_container`, which the same test asserts is
empty at `:172` and which gates `_wait_enemies_cleared` (`level_director.gd:131`). They should be
gone long before (lifetime 0.5 s, then two more sections and a `< 10 s` budget asserted at
`:168`), and the station's own chain already lands there — but the risk table's "~0.5 s and the
section poll already tolerates it" should name this specific test and its four extra children, so
that whoever implements it knows where to look if the gate reds.

---

# Review — round 2

VERDICT: APPROVED

All five required changes are in, and I re-verified each one against the code rather than against
the plan's description of it. The lead change (change 0) I verified *end to end*: I applied it to
the real component in a scratch working copy, re-ran the round-1 probes, and restored the file
(`git status` clean afterwards). It works, and it preserves the `at` contract exactly.

Implement it. Four small corrections below are for the implementer to fold in as they go — none
is worth another review round, and none changes the design.

## The five required changes, re-verified

- **R1 — change 0 is present and correct.** `3-plan.md:35-47` leads with it. With the assignment
  moved after `container.add_child(p)`, on the real component: a real `RaceWall` under a `Track`
  at `position = (0, -777)` explodes at **`(320, -4977)`** — the wall — instead of `(320, -5754)`;
  a container with `position = (300, 50)` **and** `rotation = 0.7` puts the blast on the entity at
  `(291.94, 121.66)`; and `explode(Vector2(999, 111))` still lands at exactly `(999, 111)`, so
  `StationDeathSequence`'s `at` contract (`station_death_sequence.gd:197`) is untouched. The
  "safe because the assignment is synchronous before any frame" reasoning at `:42-44` holds.
- **R2 — the table is now a reliable enumeration.** `grep -rn "ExplosionEffect.new()" --include=*.gd`
  returns exactly ten hits and exactly the ten rows in `1-context.md:32-41`. The duplicate
  `space_station.gd` row is gone, `station_death_sequence.gd:179` is present and correctly noted
  as the only caller that passes `at`, and the `asteroid_base.gd:35` / `race_wall.gd:24` /
  `station_turret.gd:79` verdicts now match the code. Defect 3 is written up as first-class
  (`1-context.md:72-90`) with the probe output.
- **R2c — the `$Turrets` claim is now accurate.** `1-context.md:103-109` and `3-plan.md:97` both
  state plainly that `space_station.gd:137-143` filters and that the incident was in a test
  helper. Correct. (The *replacement* rationale needs one more pass — see C1.)
- **R3 — the test plan can now fail on R1.** `test_particles_land_at_the_actor_position_under_a_transformed_container`
  (`:151-154`, non-identity **and** rotated, asserting `global_position`) and
  `test_a_race_wall_under_the_real_track_offset_explodes_at_the_wall` (`:187-190`) are both tests
  that red on today's build — I confirmed both conditions by probe. The loud-failure test now
  asserts through `assert_push_warning()`, and **I verified that mechanism works in this
  project's GUT**: a throwaway test in `tests/unit/` passed 2/2 using
  `assert_push_warning()` / `assert_push_warning_count()`, including capturing a warning raised
  from *production* code (`race_participant.gd:41`'s "No RaceDirector"), so the tracker is not
  limited to warnings pushed by the test file itself. Throwaway file deleted.
  `test_a_destroyed_turret_leaves_its_blast_outside_the_hull` (`:194-196`) is also a test that
  reds today, on both halves of its assertion.
- **R4 — accepted with the right diagnosis.** Risk row `:209` and build step 5 `:133-134` name
  `_build()` (`test_damage_reaction.gd:14-27`), the two affected tests (`:80`, `:92`) and
  `addons/gut/gut.gd:390`.
- **R5 — docs step present.** Build step 10 (`:140-141`) plus the "Docs to update" list
  (`:214-228`), which matches the sites I found and correctly adds
  `docs/architecture/modules/global.md`.
- **Style note accepted, and it checks out.** From a real turret,
  `get_parent().get_parent() as SpaceStation` returns the station and `== t.owner` is `true`
  (probe), and that node's parent is the enemy container. The turret is authored at
  `space_station.tscn:93-106` as `Turrets/Turret*`, so the two hops are exact. Guarding both the
  station and its parent is right.

## The two deferrals — I agree with both

1. **The per-level `Effects` layer stays out.** Right call, and change 0 strengthens it: the
   *visible* misplacement is fixed by a one-line change, so what the layer buys is architectural
   separation plus not inflating `level_director.gd:131`'s poll — real, but no longer urgent.
   Against that it moves `ENEMIES_CLEARED` timing that `test_level_1_sequence.gd:161-163` and
   `:172` pin, needs three level scenes wired, and needs a defined non-silent fallback or it
   reintroduces research finding 5's failure class. Correctly sequenced second.
2. **`explode(at, container)` stays an appended optional parameter.** Agreed. It leaves the nine
   other call sites untouched, and both alternatives are worse here: an options dict is untyped
   magic strings (the thing finding 5 rejects) and would sit next to a parameter that *already*
   carries a documented GDScript-4 casting trap (`explosion_effect.gd:48-50`), while a separate
   method either duplicates the body or forwards `at` anyway. Worth revisiting only if a third
   parameter ever appears.

## Corrections to fold in during implementation (not blocking)

- **C1. The turret rationale is now wrong in the other direction.** `3-plan.md:97` says the FX
  "inherit the station's translation and rotation", and `:46-47` says change 0 makes the turret
  change matter "for *look* rather than only for hygiene". Both overstate it.
  `CPUParticles2D.local_coords` defaults to **false** (probed), and `explode()` never changes it,
  so emitted particles live in global space and are not dragged by later hull motion; with
  `explosiveness = 0.9` (`explosion_effect.gd:60`) the bulk of the burst emits on the first frame.
  And with change 0 alone, a particle parented into `$Turrets` on a station at `(640, 200)` rotated
  `0.6` rad still lands at the turret's world position `(620.19, 94.36)` (probed) — change 0 fixes
  the look by itself.

  What actually remains, and is sufficient: the FX sit **inside an entity that gets freed**, which
  violates the component's own stated premise at `explosion_effect.gd:5-6`.
  `SpaceStation._finish_death()` frees the hull and takes any live turret blast with it — exactly
  the last-turret-then-core kill order `test_level_1_sequence.gd:141-144` performs — plus the
  trailing ~10% of particles emitted from a node that has since moved, plus the test-helper
  hygiene already documented. Restate `:97` and `:46-47` that way. Keep the change.
- **C2. Guard order in change 2's fallback.** Check `is_instance_valid(container)` *before*
  `container.is_inside_tree()`: a freed node passed as `container` makes the `is_inside_tree()`
  call itself `Invalid call. Nonexistent function ... on a previously freed instance`, which is in
  `/agent/verify.sh`'s `FATAL` regex. Round 1's draft said "freed"; revision 2's `:80-81` says
  "not inside the tree", so the freed case now needs the guard order made explicit.
- **C3. State the right reason for rejecting a detached container.** It is not a crash — I probed
  it: `container.add_child(p)` followed by `p.global_position = …` on an out-of-tree container
  errors nothing and computes the transform correctly (`p.position = (43, 53)` for a container at
  `(7, 7)`). The reason to fall back is that such a particle never renders, never emits
  `finished`, and therefore never self-frees — a leak. Have
  `test_a_null_or_detached_explicit_container_falls_back_to_the_default` assert for that reason.
- **C4. Line-number nit.** `1-context.md:147` cites `station_death_sequence.gd:196`; that is the
  `if _fx != null and is_instance_valid(_fx):` guard — the `explode()` call is `:197`.

## Scope

Still one session: four component edits (three of them a few lines), two call sites, one
`_build()` fix, two new test files, docs. Build order `:127-141` is correct — change 0 before
change 1 means each new test flips green for a reason the implementer can point at.
