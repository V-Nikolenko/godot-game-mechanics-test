# Review — Station core hurtbox: 88 x 240 or the whole hull?

VERDICT: CHANGES_REQUESTED

Reviewed against the tree at `9cccfe6` (branch `agent/auto-dev`). Every measurement in
`1-context.md` was re-derived from the scene files, and the Godot API claims in `3-plan.md` were
re-run headless on the installed 4.6.3. **The design verdict is correct and I would not overturn
it.** The blocking problems are all in the *deliverable*: the plan pins the conclusion and leaves
the premise it rests on untested and unrecorded, and its one genuinely adversarial check is a
manual ritual that leaves nothing behind.

---

## What I verified independently (all of it holds)

| Claim | Where I checked | Result |
|---|---|---|
| One 240x240 `RectangleShape2D_ss` serves both the body collider and the core `HurtBox` | `assault/scenes/enemies/space_station/space_station.tscn:22-23`, `:71-72`, `:80-81` | Confirmed. Plan cites `:16-17` in the backlog text; the real lines are `:22-23`. |
| Turrets at `(±76, ±76)`, `CircleShape2D` r26 | `space_station.tscn:95-105`, `station_turret.tscn:8-9`, `:23-24` | Confirmed. x-extent `[50, 102]`, so the proposed `[-44, 44]` core is indeed disjoint. |
| Hull art is 256x256 | PNG IHDR of `assault/assets/sprites/enemies/station_core.png` | Confirmed (turret art is 64x64). |
| `StationTurret._destroy()` closes the turret hurtbox | `assault/scenes/enemies/space_station/station_turret.gd:73-77` | Confirmed — `monitoring`, `monitorable` and the shape are all disabled. The phase-2 "66 % goes dead" figure follows (88/256 = 34.4 % left). |
| The hull rotates through phase 2 at 0.5 rad/s | `station_laser_phase.gd:_physics_process`, `space_station_config.tres` `laser_rotation_speed = 0.5` | Confirmed. |
| A player bullet is **not** consumed by the first hurtbox it overlaps | `assault/scenes/projectiles/bullets/bullet.gd:45-49`, `:84`; `bullet.tscn:55-56`; `assault/scenes/player/weapons/behaviors/straight_behavior.gd:22`; `assault/scenes/player/weapons/modes/default.tres:12`; only two `expired` listeners repo-wide (`global/components/bullet_pool.gd:56`, `sniper_enemy.gd:102`) and neither is on the player path | Confirmed, and it is load-bearing — see finding 1. |
| Both hurtboxes can actually see the player bullet | bullet `HitBox` layer 64 / mask 513 (`bullet.tscn:44-45`); core `HurtBox` mask 1121 (`space_station.tscn:76`); turret mask `97 \| 1024` = 1121 (`station_turret.gd:35`) | Confirmed. |
| Active epic `boss-fight-escalation-shared-hull-flying-laser-projectors-de`, task 1 verbatim | `BACKLOG.json:315-322` | Confirmed, `"status": "active"`, task head is exactly *"1. Every shot that lands on the station hurts the station."* |
| `test_contact_hitbox_geometry.gd` is a real harness precedent with an 11-entry roster incl. `ally_fighter` | `tests/integration/test_contact_hitbox_geometry.gd:34-80`, `:84-107`, `:154-165` | Confirmed. |
| No existing test already covers hurtbox geometry | grepped `tests/` for `get_rect()` / `encloses` — zero hits; `tests/integration/test_space_station.gd` has nine tests, all driving `received_damage` directly | Confirmed, and `ENEMY.md:467` already flags this as a known gap. The plan does not reinvent anything. |
| `Shape2D.get_rect()`, `Transform2D * Rect2`, inclusive `Rect2.encloses()` on 4.6.3 | ran headless: `CircleShape2D(26).get_rect()` -> `(-26,-26,52,52)`; `RectangleShape2D(240,240)` -> `(-120,-120,240,240)`; `Transform2D.scaled(2.289) * rect` works; `a.encloses(a)` -> `true` | Confirmed. |

**I also prototyped the proposed sweep** (throwaway script outside the repo, loading all 11 scenes
and comparing `cs.transform * cs.shape.get_rect()`). It reproduces the plan's numbers and adds one
correction the plan should absorb:

```
ally_fighter        body 29.405  hurt 29.936   covers=true   covers_tol1=true
bomber              body 44.0    hurt 44.0     covers=true   covers_tol1=true
bonus_drone         body 24.0    hurt 24.0     covers=true   covers_tol1=true
drone_interceptor   body 61.600  hurt 61.5999  covers=FALSE  covers_tol1=true
gunship             body 83.079  hurt 82.405   covers=FALSE  covers_tol1=true
interceptor         body 50.400  hurt 50.3999  covers=FALSE  covers_tol1=true
kamikaze_drone      body 20.0    hurt 20.0     covers=true   covers_tol1=true
light_assault_ship  body 57.200  hurt 57.200   covers=true   covers_tol1=true
ram_ship            body 72.0    hurt 72.0     covers=true   covers_tol1=true
space_station       body 240.0   hurt 240.0    covers=true   covers_tol1=true
sniper_enemy        body 40.320  hurt 40.616   covers=true   covers_tol1=true
```

So the tolerance is not a nicety for the gunship alone — **three** of eleven fail bare
`encloses()`, two of them by ~1e-5 px of float noise. The 1.0 px constant is necessary and
sufficient. (Plan `3-plan.md:47-49` says "11 of 11 ... at the same scale"; exactly-equal is 5 of
11. The conclusion is unaffected, but the sweep must be written with the tolerance from the first
line, not added after a red run.)

---

## The design verdict: I agree, keep the full-hull hurtbox

Not a rubber stamp — I looked for the case for narrowing and it is not there:

- The only benefit is suppressing one redundant hull flash on a shot that lands on a turret
  anyway. I confirmed the bullet survives the core overlap, so **nothing about turret reachability
  changes**; the change is purely cosmetic in phase 1.
- The cost is real and unmitigable at the hurtbox layer: 64 px of a 256 px hull (25 %) that
  swallows shots with no response in phase 1, and 66 % in phase 2 with all turret hurtboxes
  closed — at the exact moment the fight has told the player the core is open.
- It is directly hostile to `BACKLOG.json:320-322`, an already-approved active task whose whole
  point is that every landed shot moves one number.
- The genre citations in `2-research.md` support what they are used for. The Boghog "enemies should
  have big hitboxes" line and the Gradius Wiki "walls or force fields the player must break
  through" line both argue for armour-as-object or armour-as-rule, never armour-as-absence. The
  one unverifiable source (TV Tropes *Hitbox Dissonance*) is explicitly labelled as an unverified
  search-index summary and no argument leans on it. Tradeoffs are stated on every row, including
  one that cuts against the plan (armour-as-object costs an HP pool and art).

The rejected-alternatives table is honest, and the second row ("narrow it, plus real armour-plate
hurtboxes") is the genuinely better long-term design — correctly deferred, because task 1 of the
active epic is about to collapse five HP pools into one.

---

## Blocking findings

### 1. The plan pins the conclusion and leaves its premise untested — and the premise is an open backlog item

`3-plan.md:28-35` and `1-context.md`'s "Conventions that constrain this" both rest the entire
verdict on: *a player bullet crosses the deflecting core and still hits the turret behind it.*
I verified that is true today (`bullet.gd:84` emits `expired` with no listener on the player path;
`straight_behavior.gd:22` bypasses `BulletPool`; `default.tres:12` sets `range_px = 0.0`).

But the repo's own backlog files that same behaviour as **probably a bug**:
`BACKLOG.json`, item `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`, state `todo`
— *"the player's default shot is effectively infinitely piercing against stacked hurtboxes ...
That is probably not intended and is a real balance question for multi-part targets."*

If a future cycle "fixes" that — makes a bullet die on its first hurtbox overlap — then with a
full-hull core hurtbox, in phase 1 every shot aimed at a turret is absorbed by the core (the core
rect's bottom edge is at y=+120, the turret circles start at y=+102, so at 900 px/s the core hit
lands one to two physics frames earlier), deflects for 0, and dies. **The turrets become
unkillable and the boss becomes unkillable.** All five proposed tests stay green, because they
measure rectangles.

This is precisely the failure mode this project keeps paying for: `ENEMY.md:467-472` already
records the matching open gap — *"a core no bullet could ever hit passes all nine tests ... Closing
it needs a test that instances `assault/scenes/projectiles/bullets/bullet.tscn` and steps
physics"* — and `ENEMY.md:474-479` records that the not-consumed premise "was got wrong twice
during sub-item 2's review".

**Required:** the deliverable must pin the premise, not only the geometry. Preferred: add one
physics-level test — instance `bullet.tscn` at the station's local `x = 76` below the hull, step
~6 physics frames, assert the turret's `Health` dropped, the station's did not, and
`armor_deflected` fired. That single test is what makes "no" safe, it closes the coverage gap
`ENEMY.md` has been carrying since sub-item 2, and it is a few lines on a harness that already
instantiates the station. If the reviewer of the *next* plan disagrees about cost, the absolute
minimum is a named "load-bearing dependency" paragraph in the `ENEMY.md` decision record that
cross-links the open backlog item, plus the same note in the new test file's header — but a prose
warning is strictly weaker than the test the docs already ask for.

### 2. Build step 2 is a manual ritual that leaves nothing in the suite; make the negative case a real test

`3-plan.md:99-103` proves the sweep bites by hand-editing `space_station.tscn` to 88x240, running
the suite, then `git checkout --`-ing the scene, with the outputs pasted into `5-progress.md`.
Two problems: the evidence is prose that decays the moment the helper changes, and it mutates a
tracked scene inside an autonomous loop that commits and pushes uncommitted work.

The same proof is available with no scene edit and permanent value: instantiate the station,
replace **the instance's** hurtbox `CollisionShape2D.shape` with a fresh
`RectangleShape2D(88, 240)`, call the same coverage predicate the sweep uses, and assert it
returns `false` naming the missing 76 px. Requires factoring the comparison into a helper
returning `bool` rather than inlining `assert_true` — which is a better shape anyway. That turns
`3-plan.md:123-125`'s "boundary case, explicitly: 88 x 240 itself" from a one-off into a gate.

---

## Non-blocking findings

### 3. The roster becomes a third hand-maintained copy, and nothing checks it is complete

`tests/integration/test_enemy_contact_damage.gd:55+` and
`tests/integration/test_contact_hitbox_geometry.gd:34-80` each hold their own literal roster;
this plan adds a third. Neither existing file has a completeness guard, so a new enemy is silently
uncovered — which undercuts `3-plan.md:74-76`'s claim that a project-wide sweep "stops the same
question being asked once per enemy". Two cheap improvements, either or both: extract the roster
to `tests/helpers/` (the directory exists — `player_stub.gd`, `save_sandbox.gd` — and is exempt
from the `test_*` collection rule), and/or add a `DirAccess` guard that every
`assault/scenes/enemies/<dir>/<dir>.tscn` appears in the roster. `DirAccess` precedent:
`tests/integration/test_suite_integrity.gd:51`, `test_project_load_integrity.gd:96`.

### 4. `>= 239 px on both axes` is a magic number that will fail for the wrong reason

`3-plan.md:118`. Task 4 of the same active epic adds new station parts and task 1 re-derives the
fight's numbers; a legitimate hull resize would redden this test with a message about the 88x240
proposal. Express it relative to the body shape (`hurtbox rect covers body rect, and the body rect
is wider than the turret span at |x| = 102`) so it keeps meaning "the core spans the hull" rather
than "the core is 240".

### 5. The stated rule is broader than what the test asserts

`3-plan.md:41-42` states the rule as *"an enemy's `HurtBox` covers the hull the player can see"*,
but the assertion is `HurtBox ⊇ body CollisionShape2D`. For the station those differ: the body
collider is 240x240 against a 256x256 sprite, so 8 px per edge of visible hull is outside both.
Say what is enforced in the file header, and note the sprite/collider gap once so the next reader
does not think the sweep covers art.

### 6. The one-sided assertion cannot catch an oversized hurtbox

`3-plan.md:83-84` justifies coverage-not-equality with *"`ally_fighter` and `sniper_enemy` already
have [a larger hurtbox]"*. Measured, those deltas are 0.27 px and 0.15 px — both inside the 1.0 px
tolerance, so a symmetric assertion would pass all 11 today and be strictly stronger. One-sided is
still defensible (the plan's own research says generous enemy hitboxes are the genre norm), but the
stated reason is not the real one. Either fix the reason or take the stronger assertion.

### 7. Nit: projectile half-width

`3-plan.md:80-82` says "the player bullet's capsule is ~2.4 px wide after its root scale".
`bullet.tscn:13-17`: `CapsuleShape2D` at default radius 10, root `scale.x = 0.236342` -> 4.73 px
**wide**, 2.36 px half-width. 2.4 is the half-width, not the width. The conclusion (1.0 px
tolerance is below the smallest projectile half-width) is unchanged. Also note
`enemy_bullet.tscn:22-23` is layer 256 / mask 128, so enemy bullets never test an enemy hurtbox at
all — the player bullet is the only relevant projectile.

---

## Scope

Fine for one session as written, and still fine with finding 1 folded in: one new test file
(5 tests + 1 negative + 1 physics test), one `ENEMY.md` section, two doc-list entries. No
production code changes, no scene changes. `bash /agent/verify.sh` and
`scripts/check-test-leaks.sh` both exist and are correctly named in the build sequence.

## What approval needs

Findings 1 and 2 addressed in `3-plan.md` (test plan and build sequence updated accordingly).
Findings 3-7 are recommendations; adopting 3 and 4 is cheap and I would take them.
