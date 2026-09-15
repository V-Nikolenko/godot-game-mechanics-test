VERDICT: CHANGES_REQUESTED

## Summary

The design is sound and every factual claim I could independently verify checks out: the
per-entity layer/mask/damage table, the shape-scale values, the SubResource-id-sharing
identity claim, the "no other caller of `matching_shape()`" claim, and the UID reasoning are
all correct against the actual current code and scenes. The one real problem is in the **build
sequence**: as written, step 2 (delete `HitBox.matching_shape()`) runs before steps 6 and 7
(remove the three subclass overrides that still call it), which I confirmed experimentally
produces a hard parse error the moment any of those three scripts is loaded — not a
hypothetical, a reproduced one. That breaks the plan's own "each scene edit is immediately
verified in isolation" claim for a third of the roster during the middle of the sequence.

## Findings

### 1. Build-sequence ordering: step 2 breaks 3 of 10 entities until steps 6–7, undermining step 4's per-scene verification (blocking)

`3-plan.md` build sequence, steps 2–7:
- Step 2: delete `HitBox.matching_shape()` from `global/components/hitbox_component.gd`.
- Step 4: ten scene edits, "each immediately verified by re-running
  `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` for just that entity
  ... before moving to the next, so a mistake is caught at the file that caused it."
- Step 6: only now does `drone_interceptor.gd`/`kamikaze_drone.gd` lose their
  `_add_contact_hitbox()` overrides (which call `HitBox.matching_shape(...)` —
  `drone_interceptor.gd:146`, `kamikaze_drone.gd:58`).
- Step 7: only now does `ally_fighter.gd` lose its `_add_contact_hitbox()`
  (`ally_fighter.gd:95`, also a `matching_shape()` call).

I verified in an isolated scratch Godot 4.6 project that a script containing **any** call to a
now-nonexistent static method — even inside a function that is never invoked — fails to
*load* at all, with a hard parse error:

```
SCRIPT ERROR: Parse Error: Static function "does_not_exist()" not found in base "Foo".
ERROR: Failed to load script "res://baz.gd" with error "Parse error".
```

This is not deferred to call time; `load()` on the `.gd` (and therefore on any `.tscn` whose
root script is that `.gd`) fails immediately. Applied here: from the moment step 2 completes
until steps 6 and 7 land, `drone_interceptor.gd`, `kamikaze_drone.gd`, and `ally_fighter.gd`
all fail to load, because each still contains its own dead `_add_contact_hitbox()` body calling
the now-deleted `HitBox.matching_shape()`.

Both `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` iterate a fixed
roster covering **all** ten/eleven entities in one test function (`ROSTER` at
`test_contact_hitbox_geometry.gd:34`, `test_enemy_contact_damage.gd:54`), so every single
"immediately verified" run in step 4 — for all ten scenes, not just the three affected ones —
will show real, non-transient failures for `drone_interceptor`, `kamikaze_drone`, and
`ally_fighter` (`assert_not_null(scene, ...)` fails because `load()` returns null) for the
entire span of step 4. That directly contradicts the stated purpose of running the tests after
each scene edit ("a mistake is caught at the file that caused it") — for a third of the roster,
every check in that window fails regardless of whether the edit just made was correct. It would
also trip `test_project_load_integrity.gd` if the full gate were run at any point in this
window.

**Fix**: reorder so no intermediate state has a dangling call to a deleted method. Either:
(a) do each entity's script edit and scene edit together, entity by entity (so
`drone_interceptor.gd`'s override and `drone_interceptor.tscn`'s new node land in the same
step), and move the `matching_shape()` deletion to the very end once all four call sites are
confirmed gone (i.e. swap the position of today's step 2 with today's step 8-ish), or
(b) move today's steps 6 and 7 to before step 4, so all four call sites are gone before any
scene-edit verification pass begins. Either way, `HitBox.matching_shape()` should be the
**last** thing deleted, not the first.

### Everything else checked out

- **Per-entity table** (`1-context.md` lines 60–76): every layer/mask/damage-default value and
  every shape scale value matches the actual `.tscn`/`.gd` content, confirmed by direct
  inspection of all ten scenes and nine scripts (`base_enemy.gd:75–79`,
  `drone_interceptor.gd:141–148`, `kamikaze_drone.gd:53–60`, `ally_fighter.gd:90–95`, and the
  five re-apply sites at `bomber.gd:23–26`, `gunship.gd:50–53`, `light_assault_ship.gd:21–24`,
  `ram_ship.gd:22–25`, `space_station.gd:124–127`). No table error found.
- **SubResource identity claim** (the core technical premise): confirmed correct. Not only is
  this standard Godot `.tscn` deserialization behaviour (one object per `SubResource` id per
  scene file), it is already load-bearing, tested-by-implication behaviour in this exact
  codebase — `tests/integration/test_enemy_hurtbox_geometry.gd:224–227` explicitly documents
  that `space_station.tscn` "shares one `RectangleShape2D_ss` sub-resource between the body
  collider and the core HurtBox and it is not `resource_local_to_scene`, so an in-place edit
  would resize the body too." Every one of the ten scenes already shares one `SubResource` id
  between its body `CollisionShape2D` and its `HurtBox`'s `CollisionShape2D` today (confirmed by
  reading all ten), so the plan's approach reuses an already-proven-live pattern, not merely a
  theoretical one. The claim that the two existing tests need zero assertion changes for this
  reason holds.
- **`HitBox.matching_shape()` deletion safety**: confirmed by `grep` — the only callers anywhere
  in the project are the four sites the plan removes; no test instantiates it directly
  (`tests/unit/test_hitbox_hurtbox.gd` does not reference it). Safe to delete once (and only
  once) all four callers are actually gone — see Finding 1 for the timing problem.
- **UID reasoning**: `hitbox_component.gd.uid` on disk is `uid://deqgbl6m44nrj`, and it's already
  referenced this same way (bare `ext_resource` citation of an existing script's real uid) from
  7+ other `.tscn` files project-wide, including the asteroid family this plan is modelled on.
  No new uid is minted; the CLAUDE.md convention is not violated.
- **Insertion point**: "after `HitFlashAnimationPlayer`" (after `Health` for `ally_fighter`) is
  consistent across all ten scenes as read; no scene indexes children by position
  (`get_child(i)` not used anywhere in these scripts) and no `%unique_name` references the
  affected region, so node-order insertion is safe.
- **`_make_corpse_harmless()` / space_station risk**: the plan's own risk section hedges with
  "`tests/integration/test_space_station.gd` / `test_station_death_handoff` (if present)" — the
  actual test that exercises this exact path is `tests/integration/test_station_death_sequence.gd`,
  specifically `test_the_corpse_cannot_ram_the_player` (lines 111–129), which does exist and
  does search `_station.get_children()` for a `HitBox` the same way `_make_corpse_harmless()`
  does. This is a minor citation gap (the plan didn't find the actual test by name), not a
  functional risk — `bash /agent/verify.sh` runs the whole suite including this file regardless,
  so the behaviour is still gated. Worth naming correctly when the plan is revised, but not
  blocking on its own.
- **Drone self-destruct wiring** (`_on_contact_hit` via `area_entered`): the plan's step 6
  correctly moves the `.connect()` call into `_ready()` off the typed `contact_hit_box` var
  rather than dropping it — no signal-connection regression found.
- **Bonus drone**: confirmed `bonus_drone.tscn` has no `ContactHitBox`-shaped node and needs no
  scene edit; deleting `bonus_drone.gd`'s no-op override is inert once the base no longer calls
  it.

## What to change before this proceeds

Only Finding 1. Fix the build-sequence ordering (interleave script+scene edits per entity, or
move all four call-site removals before any scene-edit verification pass, with
`matching_shape()` itself deleted last), then this plan is ready to implement.

## Round 2

VERDICT: APPROVED

### Summary

The revision fixes round 1's blocking finding. I independently re-walked the new step
sequence (`3-plan.md` steps 1–8) against the current code and confirmed the invariant that
matters holds throughout: `HitBox.matching_shape()` (`global/components/hitbox_component.gd:20`)
is not deleted until step 8, and every script that still contains a call to it after step 2 has
that call removed in the very step that also lands its scene edit — step 4 for
`drone_interceptor.gd:146`, step 5 for `kamikaze_drone.gd:58`, step 6 for
`ally_fighter.gd:95`. At no point between step 2 and step 8 does any live `.gd` file contain a
call to an already-deleted method, so the reproduced parse error from round 1
(`load()` failing on a static-method-not-found error) cannot occur at any intermediate point.
I also confirmed the converse doesn't happen either: no script calls a not-yet-deleted method
that would need to exist earlier than it does — `matching_shape()`'s signature is untouched
until the single deletion in step 8, so every call site that hasn't been edited yet is still
calling a real method the whole time.

I also checked the within-step ordering the plan doesn't spell out (e.g., for step 4, does it
matter whether `drone_interceptor.tscn` or `drone_interceptor.gd` is edited first). It doesn't:
`base_enemy.gd`'s `_ready()` no longer calls `_add_contact_hitbox()` as of step 2, so
`DroneInterceptor._add_contact_hitbox()` (the override at `drone_interceptor.gd:141-148`) is
already dead code — never invoked from anywhere — from step 2 onward, regardless of whether the
scene or the script half of step 4 lands first. Same for `kamikaze_drone.gd` and step 5. Only
`ally_fighter.gd` is different in kind: it is not a `BaseEnemy`, so its own `_ready()`
(`ally_fighter.gd:31`) keeps calling its own `_add_contact_hitbox()` directly and keeps working
via `matching_shape()` right up until step 6 edits it — confirmed unaffected by step 2's
`base_enemy.gd` edit.

### Finding 1 (non-blocking — prose accuracy): "a red result is attributable to this entity's edit" overstates what step 3's re-runs will actually show

Both invariant tests iterate a single fixed `ROSTER` inside one test function —
`test_contact_hitbox_geometry.gd:110` (`test_every_contact_hitbox_matches_its_body_shape`, 11
entries) and `test_enemy_contact_damage.gd:143` (`test_every_enemy_contact_hitbox_matches_its_config`,
10 entries, no `ally_fighter`) — and GUT's `assert_*` calls don't abort the loop on the first
failure, so a single run reports one failure line per entry that's currently broken, not just
one.

Step 2 removes `_add_contact_hitbox()`'s call from `base_enemy.gd:52`, which is the sole
dispatch point for **every** `BaseEnemy`-based entity's contact hitbox, including the two that
override it (`drone_interceptor`, `kamikaze_drone` — see above, their overrides go dead the
same moment, not just at their own step 4/5). From that point until each entity's own step
lands, that entity has no contact hitbox at all and fails `assert_not_null(hb, ...)` in both
files. Concretely: the first test run in step 3 (after e.g. `bomber` alone is migrated) will
also show failures for `gunship`, `light_assault_ship`, `ram_ship`, `space_station`,
`interceptor`, `sniper_enemy`, `drone_interceptor`, and `kamikaze_drone` — up to eight reds that
have nothing to do with the edit just made, alongside whatever the `bomber` edit itself
produced. The window closes at different points per file: step 5 for
`test_enemy_contact_damage.gd` (its roster's last not-yet-migrated `BaseEnemy` entity,
`kamikaze_drone`, lands there), step 6 for `test_contact_hitbox_geometry.gd` (its roster also
carries `ally_fighter`, which is unaffected by step 2 and stays green throughout — not part of
this window at all).

None of this breaks anything mechanically — the tests still run to completion (no parse
failure, no crash) and every failure message names its entity (`"%s: has no contact HitBox..."
% entry["name"]`), so an implementer working through step 3 in order can still tell "my
just-edited entity is red" from "an entity I haven't reached yet is red" by reading the
messages. But the plan's literal claim — a red result at this point is attributable to *this*
entity's edit — is not accurate for most of the build sequence: most reds in that window are
attributable to entities not yet reached, not to the edit just made. Recommend tightening the
prose in step 3 (and noting the same for steps 4–5) to say something like: "expect failures for
every `BaseEnemy`-based entity not yet migrated in this window; treat only a failure naming the
entity just edited, or an unexpected failure/pass for an already-migrated one, as a real
signal" — a documentation fix, not a sequencing fix, since the underlying ordering is otherwise
sound.

### Spot checks of round 1's other findings against current code

- **SubResource sharing, re-confirmed on a scene round 1 didn't quote directly**:
  `gunship.tscn:63-75` — body `CollisionShape2D` and `HurtBox`'s `CollisionShape2D` both
  reference `SubResource("CircleShape2D_gs")`, confirming the identity-sharing pattern the whole
  plan rests on is real in the actual file, not just in the context doc's prose.
- **Re-apply call sites unchanged since round 1**: `gunship.gd:51-52`, `ram_ship.gd:23-25`,
  `space_station.gd:124-127` (including the `_make_corpse_harmless()` search at
  `space_station.gd:236-237`) all still do the plain `for child in get_children(): if child is
  HitBox:` pattern round 1 described, no `matching_shape()` call in any of the three — confirms
  step 3's claim that these five scripts carry no risk of the parse-error class of bug.
- **Insertion point**: `bomber.tscn`'s node order is `Sprite2D, CollisionShape2D, HurtBox,
  Health, HitFlashAnimationPlayer` and `ally_fighter.tscn`'s is `AnimatedSprite2D,
  CollisionShape2D, HurtBox, Health` (no flash player) — matches the plan's "after
  `HitFlashAnimationPlayer` (after `Health` for `ally_fighter`)" placement exactly.
- **Step 8's grep expectation**: ran `grep -rn "matching_shape" --include=*.gd .` fresh —
  exactly the definition (`hitbox_component.gd:20`), the four real call sites being removed
  (`ally_fighter.gd:95`, `base_enemy.gd:79`, `kamikaze_drone.gd:58`, `drone_interceptor.gd:146`),
  and three comment mentions in the two test files. Matches the plan's prediction exactly.

### Verdict rationale

The one blocking issue from round 1 is genuinely fixed, not just asserted fixed — I reproduced
the reasoning independently against the current file contents rather than trusting the plan's
"Revised after review round 1" paragraph. Finding 1 above is real but cosmetic (a documentation
clarity issue, not a functional or ordering defect), so it doesn't block. Plan is ready to
implement as written; tightening the step 3 prose per Finding 1 is optional and can happen
inline during implementation rather than requiring another review round.
