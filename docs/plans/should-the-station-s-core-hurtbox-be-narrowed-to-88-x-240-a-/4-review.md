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

---

# Review — round 2

VERDICT: APPROVED

Reviewed `3-plan.md` **Revision 2** against the tree at `116c16a` (branch `agent/auto-dev`).
Scope per the round-2 brief: whether the revisions close blocking findings 1 and 2, whether the
newly-specified tests are implementable and non-vacuous, whether the absorbed `[R1]` corrections
are right, and whether the scope still fits one session. The design verdict was settled in round 1
and is not re-litigated here.

**Both blocking findings are closed, and I confirmed the two new physics tests actually work by
running them.** Everything below is a note for the implementer, not a gate.

## Blocking finding 1 — CLOSED, and verified by running it

`3-plan.md:89-108` and the test plan at `:167-179` replace the prose warning with two real physics
tests. I did not take the frame arithmetic on trust — I built the exact scenario the plan
describes as a throwaway `SceneTree` script and ran it on the installed 4.6.3.

Test A (`godot --headless --path . -s <probe>.gd`, station instanced under a `Node2D` container,
`bullet.tscn` added to the container at global `(76, 200)`, one `await physics_frame` per step):

```
station pos (0.0, 0.0) scale (1.0, 1.0) health 600/600
turret Turret3 gpos (76.0, 76.0) hp 120
bullet scale (0.236342, 0.168031) hitbox layer/mask 64/513 dmg 50
frame 4  bullet_y=140.0 valid=true turretHP=120 stationHP=600 deflects=0
frame 5  bullet_y=125.0 valid=true turretHP=120 stationHP=600 deflects=1
frame 7  bullet_y=95.0  valid=true turretHP=70  stationHP=600 deflects=1
frame 12 bullet_y=20.0  valid=true turretHP=70  stationHP=600 deflects=1
```

Every assertion the plan names holds: 15.0 px/frame exactly (`project.godot` does not override
`physics_ticks_per_second`, so 60 Hz); `armor_deflected` fires once at frame 5; the lower-right
turret drops **120 -> 70, exactly the bullet's 50**, at frame 7; the station stays at 600; and
`is_instance_valid(bullet)` is `true` the whole way — the premise itself. 12 frames is comfortably
inside the safe window: the bullet only reaches the *upper* turret's rim (`y = -102`) at frame ~16,
so anything from 8 to 16 frames gives "exactly 50".

Test B (kill all four turrets, bullet at global `(0, 200)`, 14 frames):

```
armored=false station hp 600 rot 0.0166666675359
f4  y=140.0 hp=600 rot=0.050
f5  y=125.0 hp=550 rot=0.058
f14 y=-10.0 hp=550 rot=0.133
```

600 -> 550, once. Also confirmed: `container.queue_free()` at the end leaves **no** `leaked` /
`orphan` / `ERROR` / `WARNING` lines on stderr, so the bullet-never-frees-itself risk
(`3-plan.md:202`) is correctly mitigated by parenting to the autofreed container.

Supporting facts the plan asserts, each checked directly:

- Station `Health` starts at 600 — `space_station.tscn:86-87` **and** `space_station_config.tres`
  `max_health = 600`; turrets 120 (`station_turret.tscn:29-30`, config `turret_health = 120`).
- Player bullet damage really is 50 — `bullet.tscn:44-47` (`damage = 50` on the HitBox),
  `bullet.gd:8` `@export var damage: int = 50`, `modes/default.tres:14`.
- `armor_deflected` is a real signal with the stated arity — `space_station.gd:22`,
  `signal armor_deflected(damage: int)`, emitted at `:171`.
- **`Bullet` needs nothing set before it moves.** `bullet.gd:38-50` `_physics_process` reads only
  the exported `speed = 900` default and `rotation` (0 by default = straight up); `_ready()`
  (`:33-36`) pushes `damage` to the child HitBox on its own. No `setup()`, no behavior, no pool, no
  `direction`. `straight_behavior.gd:18-22` only sets `damage`/`shooter_velocity`, both already at
  the right values. So the test cannot be vacuously green from a bullet that never moves —
  confirmed empirically above.
- Layers/masks let the bullet touch both hurtboxes — bullet HitBox layer 64 / mask 513
  (`bullet.tscn:44-45`); core `HurtBox` layer 512 / mask 1121 (`space_station.tscn:75-76`); turret
  `HurtBox` layer 512, mask overwritten to `97 | 1024 = 1121` in `station_turret.gd:34-35`.
- **No scale or `WORLD_SCALE` distortion in the harness.** The probe printed
  `station scale (1.0, 1.0)`, `station pos (0,0)`, turrets at global `(±76, ±76)`. `BaseEnemy` has
  no `_physics_process` at all (`base_enemy.gd`, 66 lines, none), so the station does not drift;
  local == container-local == global. `ArenaCamera.WORLD_SCALE` applies only to wave spawn offsets,
  as `ENEMY.md` states.

## Blocking finding 2 — CLOSED

`3-plan.md:155-158` and test-plan row `test_the_88x240_proposal_fails_this_sweep` (`:191`) replace
the hand-edit-and-`git checkout` ritual with an in-memory swap on the instance. No tracked `.tscn`
is touched, and the boundary case becomes a permanent gate. The arithmetic is right: body rect is
`(-120,-120, 240,240)` (measured, below), an 88-wide core is `[-44, 44]`, shortfall 76 px per side.

One footgun the implementer must avoid — see note N1.

## `[R1]` corrections absorbed in revision 2 — all correct

| Claim | Checked | Result |
|---|---|---|
| Enemy bullet capsule `radius = 2.0` at `enemy_bullet.tscn:6-7` | file | Confirmed (`radius = 2.0`, `height = 10.0`), and layer 256 / mask 128 at `:23-24` |
| Player bullet: default-radius-10 capsule under root `scale.x = 0.236342`, `bullet.tscn:13-17` | file | Confirmed; the `sub_resource` is at `:13-14` and the root `scale` at `:16-17`. 4.73 px wide / 2.36 px half-width |
| `ENEMY.md:467-472` is the coverage gap, `:474-479` the not-consumed note | file | Confirmed verbatim, both ranges exact |
| `space_station.tscn:22-23` / `:71-72` / `:80-81` | file | Confirmed |
| `bullet.gd:84` emits `expired` with no free; the only `queue_free()` is `:49`, gated on `range_px` | `grep -n` | Confirmed: `expired.emit()` at 48, 52, 75, 84; `queue_free()` at 49 and 76 (76 is the `unlimited_pierce` asteroid branch, not the player default path) |
| Extents table: 5 of 11 exactly equal, 3 of 11 fail bare `encloses()`, max delta 0.67 px | ran the sweep headless over all 11 scenes with `cs.transform * cs.shape.get_rect()` | Confirmed exactly. `covers=false` for `drone_interceptor`, `gunship`, `interceptor`; `gunship` hurt 82.405 vs body 83.079. The 1.0 px tolerance is load-bearing from line one, as the plan now says |
| `test_suite_integrity.gd:51`, `test_project_load_integrity.gd:96` are the `DirAccess` precedent | files | Confirmed, both are `var dir := DirAccess.open(dir_path)` |
| `test_station_laser_phase.gd:174-207` places a real layer-128 stub `HurtBox` in a beam's path | file | Confirmed (`PlayerProbe` + `_add_player_probe`, `probe.collision_layer = 128`) |

## The two structural guards — both implementable, neither vacuous

**`DirAccess` completeness guard** (`3-plan.md:193`). Verified by listing the tree:
`assault/scenes/enemies/` contains exactly ten directories — `bomber`, `bonus_drone`,
`drone_interceptor`, `gunship`, `interceptor`, `kamikaze_drone`, `light_assault_ship`, `ram_ship`,
`sniper_enemy`, `space_station` — and **every one has `<dir>/<dir>.tscn`**. The only non-directory
entries are `base_enemy.gd` and `enemy_path_mover.gd` (plus their `.uid`s), which
`DirAccess.get_directories()` does not return, so there are no false failures from shared/`.gd`-only
dirs. The guard passes today against the plan's 11-entry roster (10 enemies + `ally_fighter`, which
lives in `assault/scenes/allies/` and is a legitimate extra). See notes N2 and N3.

**Vacuity guard** (`3-plan.md:195`). Confirmed non-vacuous — I measured the composed
`hurtbox.transform * shape.transform` for all 11:

```
ally_fighter       non-identity   covers=true    hurt 29.936  body 29.405
bomber             identity       covers=true
bonus_drone        identity       covers=true
drone_interceptor  non-identity   covers=FALSE   hurt 61.59998 body 61.59999
gunship            non-identity   covers=FALSE   hurt 82.405   body 83.079
interceptor        non-identity   covers=FALSE   hurt 50.4     body 50.40001
kamikaze_drone     identity       covers=true
light_assault_ship non-identity   covers=true
ram_ship           identity       covers=true
sniper_enemy       non-identity   covers=true    hurt 40.615  body 40.32
space_station      identity       covers=true
```

Six of eleven have a non-identity hurtbox transform, so the guard holds with margin. The same run
confirms `test_every_roster_entry_has_exactly_one_hurtbox_with_one_shape` passes today: all 11 have
exactly one `HurtBox` direct child with exactly one `CollisionShape2D`.

## Scope

Still one session. Six tests across two files plus doc updates, no production code and no scene
changes. I reproduced the expensive half (both physics tests) in about a minute of wall clock, and
the geometry sweep is a copy of a finished harness. `bash /agent/verify.sh` and
`scripts/check-test-leaks.sh` both exist and are correctly named at `3-plan.md:161-162`.

## Notes for the implementer — none blocking

**N1. Do not mutate the shared `Shape2D`; replace the node's reference.** `RectangleShape2D_ss`
(`space_station.tscn:22-23`) is a `[sub_resource]` **without** `resource_local_to_scene`, and it is
handed to *both* the body and the core `HurtBox`. Writing `cs.shape.size = Vector2(88, 240)` in the
negative-case test would resize the body collider too **and** poison every other station instance in
the process, silently reddening the sibling station tests. `3-plan.md:191` already says "swap ... for
a fresh `RectangleShape2D(88, 240)`", which is the correct form — keep it literally, and assign to
`cs.shape`, never through it.

**N2. `test_space_station.gd` has `_kill_turret(index)`, not `_kill_all_turrets()`.** The plan hedges
("`_kill_all_turrets`-style helper", `:177`) so this is only an expectation-setter: the helper by that
name exists in `test_station_laser_phase.gd:63`, `test_station_gunnery.gd:74` and
`test_station_reinforcements.gd:82`, but not in the file being extended. Loop `_kill_turret(i)` over
`4`, or add the helper.

**N3. Implement the completeness guard over top-level directories only, not recursively.**
`light_assault_ship/` contains a `states/` subdirectory, and `bomber/` contains `bomb.tscn`. A
top-level `DirAccess.get_directories()` on `assault/scenes/enemies/` is correct and clean; the
recursive `_collect_files` idiom copied from `test_project_load_integrity.gd:96` would surface both.
(Unrelated aside: `assault/scenes/enemies/light_assault_ship/` also holds two stray
`light_assault_ship.tscn*.tmp` files. Neither a directory nor a `.tscn`, so no guard sees them, but
they are junk in the tree worth deleting in some other cycle.)

**N4. The plan's citation of the vacuity precedent is off by one function.**
`3-plan.md:195` cites `test_contact_hitbox_geometry.gd:168-183`; that range is
`test_no_body_collision_shape_uses_non_uniform_scale`. The vacuity guard to mirror is at
`:150-165` (`test_the_roster_contains_a_scaled_body_or_this_file_is_vacuous`). Copy the right one.

**N5. Turret hit lands at frame 7, not "~7 after crossing at ~6".** Measured: `armor_deflected` at
frame 5 (the capsule's ~5 px leading edge crosses `y = 120` while the centre is at 125) and the
turret hit at frame 7. The plan's "~6 / ~7" is close enough to find, but assert on `Health`, never on
frame indices — as `3-plan.md:201` already says. Any budget in `[8, 16]` frames yields "exactly 50";
below 8 it under-travels, at 17+ the *upper* turret starts absorbing a second 50.

**N6. Also update `test_space_station.gd`'s own header.** Build step 4 (`3-plan.md:159-160`) updates
`ENEMY.md`'s gap wording but not the "KNOWN COVERAGE GAP" paragraph in the test file's docstring
(`test_space_station.gd:19-24`), which will be stale the moment test A lands — it is the same claim
in the same words. Fix both, or the next reader re-opens a closed gap.

**N7. Assert against `health.max_health`, not the literal 600.** `3-plan.md:176` says "the station's
is still 600". The file's existing tests all read `_station.health.max_health` /
`STATION_CONFIG.max_health` instead; match them, so epic task 1's HP rework reddens the right test
with the right message.

**N8. Test B activates the laser phase; that is fine, but know it.** Killing all four turrets fires
`armor_broken`, and `station_laser_phase.gd:_on_armor_broken` fires the first volley **immediately**
and starts rotating the hull. Over 12 frames that is 0.117 rad (~6.7°) — I confirmed the centre-lane
bullet still lands its 50, and no beam touches the bullet (every beam sets `hit_mask_override = 128`).
No action needed; just do not add a "station rotation is 0" assertion, and keep
`scripts/check-test-leaks.sh` in the sequence as planned.

**N9. Derive the turret span rather than hardcoding 102.**
`test_the_station_core_hurtbox_spans_the_hull_not_just_the_core` (`:192`) correctly drops the magic
239 per round-1 finding 4, but "past the turret span `|x| = 102`" is itself a magic number. Read the
turrets' `position.x` and their `CircleShape2D.radius` off the instance (`76 + 26`) so a turret
reposition in epic task 4 moves the test with the scene.

**N10 (optional, not asked for). The unexamined cheaper option is adding these tests to the existing
file.** `test_enemy_hurtbox_geometry.gd` duplicates `test_contact_hitbox_geometry.gd`'s roster and
its entire `_spawn`/direct-children harness; folding the hurtbox sweep in as extra tests there would
cost one roster instead of three and make the completeness guard cover both invariants at once. I
still prefer the separate file — the header docstring is doing real explanatory work and one
invariant per file is this suite's established shape — but the plan does not mention the alternative
and should have. Not a reason to hold it.

## What was checked and found clean

- Reinvention: nothing here duplicates `global/components/`. `HurtBox` (`hurtbox_component.gd`) is
  used as-is; `HitBox.matching_shape()` is untouched; no new mechanism.
- `CLAUDE.md`: no conflict. No `uid://` is hand-typed, no `.tscn` is rewritten, no MCP UID tool is
  invoked, `updating-project-docs` is step 6, and the plan explicitly avoids mutating a tracked
  scene inside the auto-committing loop.
- The test plan can fail: test A goes red the day a bullet dies on first overlap; the negative case
  goes red if `_covers()` is loosened; the completeness guard goes red on a new enemy; the vacuity
  guard goes red if the scaled scenes are re-authored at true size.
