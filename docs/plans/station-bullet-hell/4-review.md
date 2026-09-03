# Review — station bullet-hell fire (EPIC sub-item 4a)

## Round 1

VERDICT: CHANGES_REQUESTED

The design is sound and the scope split (4a fire / 4b reinforcements) is the right call — putting
fire before reinforcements on a boss whose entire first phase is passive is well argued
(`1-context.md:5-24`). The composition rule, the config-copy discipline, the no-`randf()` rule and
the "final on-screen pixels, never `WORLD_SCALE`" rule are all respected, and nothing here
reinvents an existing `global/components/` part (I checked: there is no radial/spread pattern
anywhere — `grep TAU` over `assault/` + `global/` returns only `station_laser_phase.gd:146`,
`emp_blast_module.gd:80`, `shield_overload_module.gd:86` and two `randf` uses).

Two blockers, both concrete. Two must-fix correctness items. Then smaller notes.

---

## Blocking

### B1. `_station.add_child(_pool)` from `StationGunnery._ready()` cannot work. Reproduced on Godot 4.6.3.

`3-plan.md:77` — "So `StationGunnery._ready()` does `_station.add_child(_pool)`". This is the
load-bearing sentence of the whole pool design (`1-context.md:104-121` repeats it), and it fails
at runtime.

Godot readies children before parents by calling `Node::_propagate_ready()` on the parent, which
does `data.blocked++` *before* iterating its children. `Node::add_child()` has
`ERR_FAIL_COND_MSG(data.blocked > 0, ...)`. So a child adding a node to its own parent from
`_ready()` is refused.

Reproduced out-of-repo on this exact engine build (Godot v4.6.3.stable.official.7d41c59c4), in the
exact three-level shape (`Container → Station → Gunnery`, container added to root):

```
ERROR: Parent node is busy setting up children, `add_child()` failed.
       Consider using `add_child.call_deferred(child)` instead.
   at: add_child (scene/main/node.cpp:1709)
   GDScript backtrace: [0] _ready (res://child.gd:5)
station children after: 1   # only the Gunnery — the pool was never added
```

Consequences if implemented as written: `_pool` stays orphaned outside the tree, `BulletPool._ready()`
never runs, `_container` is never resolved, and the first volley calls `acquire()` on a pool with an
empty `_idle` array — or on `null`, depending on how the field is held. **And the gate does not catch
the error itself**: `/agent/verify.sh:12` FATAL regex is
`SCRIPT ERROR|Parse Error|Failed to load script|Cannot open file|Condition ".*" is true. (Returning|Continuing)|Invalid call|Compile Error`,
and `Parent node is busy setting up children` matches none of them. It would only surface indirectly,
via an `Invalid call` on the null pool, and only if a volley actually fires during the suite.

Note `StationLaserPhase` is *not* a precedent for this: `station_laser_phase.gd:104` does
`add_child(_volley_timer)` onto **itself**, whose `blocked` is already back to 0 by the time its own
`NOTIFICATION_READY` is delivered.

**Preferred fix, and it is simpler than what the plan has:** author the `BulletPool` as a node in
`space_station.tscn`, a direct child of `SpaceStation`, with `bullet_scene` and `pool_size` set in
the scene — and have `StationGunnery` reference it with an `@export var bullet_pool: BulletPool` /
`get_parent().get_node("BulletPool")`. The pool then readies itself with the rest of the subtree,
`get_parent().get_parent()` resolves to `enemy_container` exactly as
`bullet_pool.gd:40` requires, and the "pool must not sit under the gunnery or the turrets"
constraint is enforced by the scene file instead of by a comment. This is an alternative the plan
never considered (`3-plan.md:71-83` weighs only "pool under the gunnery" and
"`container_override` export on `BulletPool`"), and it removes the failure mode rather than working
around it. `docs/BULLET_POOL.md:37,197` documents the same contract and should get the new consumer
listed.

If you prefer to keep it in code, `_station.add_child.call_deferred(_pool)` also works (first volley
is 1.8 s away, so a one-frame delay is invisible) — but then say so explicitly and add an assertion
that the pool is in the tree before the first `acquire()`.

Either way, **integration test 7** (`3-plan.md:230-233`, "the `BulletPool` is a direct child of the
station") is now doing real work and must be written to fail if the pool is missing entirely, not
just if it is in the wrong place.

### B2. `core_ring_step = 0.21` has exactly the defect research finding 4 says to avoid, and the "design lock" test passes it.

`3-plan.md:133` justifies `0.21` with "`0.6283 / 0.21 = 2.99…`". That ratio is the *problem*, not the
proof. `2-research.md:12` (Sparen A3, which I fetched and confirmed — the page does say "you
typically need at least three bullets per ring", "the angle for the Changing mode has been adjusted
so that the angle does not divide nicely into 360 degrees" and "avoiding the creation of blind
spots") calls for a step that does **not** re-tread lanes. A ratio of 2.992 means the ring re-treads
its own lanes every **three** rings:

- spacing = `TAU/10` = 0.6283185 rad
- 3 × 0.21 = 0.63 rad → ring 4 sits 0.0017 rad (0.096°) off ring 1's lanes
- at the ~300 px radius the plan itself uses for its gap arithmetic, that is **0.5 px** of drift
- over a whole phase (≈20 rings at 2 s inside the 40–50 s budget) total drift ≈ 0.010 rad ≈ 3 px

That is a permanent safe lane, which is the precise failure the finding exists to prevent — and it
compounds with the risk already logged at `3-plan.md:279` ("Phase 2 has no aimed component, so a
safe spot is possible"). The supporting clause "0.21 rad is not a rational fraction of TAU" is not
an argument (no float is), and is also misleading: `TAU/0.21 = 29.92`, near-commensurate with the
full circle too.

**And test 12 cannot fail on this value.** `3-plan.md:249-252` asserts
`fmod(TAU / core_ring_count, core_ring_step)` is "not within 0.001 of 0 or of the step".
`fmod(0.6283185, 0.21) = 0.2083185`; `|0.2083185 − 0.21| = 0.0016815`. It clears a 0.001 tolerance by
0.0017 rad. So the test is billed as "the direct analogue of `test_volley_angles_are_deterministic`"
and as a lock against someone "tidying" the step — while green-lighting a value that is 0.27 % away
from dividing evenly. A design-lock whose tolerance is 600× smaller than the effect it locks is not
a lock.

Two changes required:

1. **Pick a step whose ratio to the spacing is far from any small rational.** The defensible choice
   is the golden-angle relation: `core_ring_step = spacing × 0.381966 ≈ 0.24 rad` (ratio 2.618, the
   most-irrational continued fraction, i.e. maximal lane coverage per ring). State the derivation in
   the `.tres` comment.
2. **Rewrite test 12 to measure what matters.** Iterate `k = 1..N` rings (N ≥ 12, i.e. more rings
   than a real phase fires), compute for each the distance from `k × step` to the nearest multiple of
   the spacing, and assert the **minimum** exceeds a meaningful fraction of the spacing — e.g.
   `0.15 × spacing` (≈5.4° ≈ 28 px at 300 px). Written that way it goes red on `0.21` today, which is
   the only evidence that it is a real test.

---

## Must fix (not blocking on their own, but wrong as written)

### C1. `tests/unit/test_radial_attack_pattern.gd` violates the stated unit/ convention.

`3-plan.md:177,191` puts it in `tests/unit/`, but it "uses a bare `Node2D` ship and a `BulletPool`
wired to `enemy_bullet.tscn`" (`3-plan.md:193-194`) — that is scene loading and a live tree.
`tests/README.md:16` says `unit/` is "One file per autoload or `global/components/` component. **No
scene loading.**" Both existing station test files say so in their own headers and put themselves in
`integration/` for exactly this reason (`test_space_station.gd:12-13`,
`test_station_laser_phase.gd:25-26`). Move it to `tests/integration/test_radial_attack_pattern.gd`.

### C2. The plan never states whether `ship.rotation` feeds the ring — and test 11 cannot tell.

Both shipped patterns fold the ship's rotation in on the non-aimed branch
(`aimed_attack_pattern.gd:29` and `gatling_attack_pattern.gd:35`, both
`Vector2.DOWN.rotated(ship.rotation)`). `3-plan.md:55-56` describes `base_angle` as an absolute
"base direction in radians" and says nothing about `ship.rotation`. This matters *specifically* here,
because `station_laser_phase.gd:123` rotates the station at 0.5 rad/s during the exact phase the
ring fires in: 2 s of hull rotation is 1.0 rad, versus a 0.628 rad spacing. An implementer copying
the shipped patterns would get a completely different attack.

Test 11 (`3-plan.md:246-247`, "two forced rings; ring 2's angles are ring 1's plus `core_ring_step`")
does not disambiguate: two rings forced back-to-back in one frame see an unchanged
`_station.rotation`, so the assertion holds under either implementation. Either way it is also
timing-fragile once real frames elapse.

Fix: state explicitly in the resource contract that `RadialAttackPattern` ignores `ship.rotation`
(a deliberate divergence from the other two patterns, and worth one comment line in the resource
header saying why), and make the ring tests set `LaserPhase.rotation_speed = 0.0` — the technique
`test_station_laser_phase.gd:283-284` already uses — or assert absolute angles against a known
`_ring_angle`.

### C3. `test_space_station.gd` parents the station straight to the test script — adding the pool changes what its container resolves to.

`test_space_station.gd:28-30` does `add_child_autofree(_station)` with no container `Node2D`. Once a
`BulletPool` is a child of `SpaceStation`, `bullet_pool.gd:40` resolves
`get_parent().get_parent()` to **GUT's own parent of the test script**, not to anything the test
owns. Nothing fires today (that file has zero `await`s, so no volley reaches 1.8 s), so this is
latent rather than live — but the plan names this resolution as the single load-bearing hazard of
the feature (`3-plan.md:71-83`) and then does not audit the two existing files that instance the
station. Add a step: route `test_space_station.gd` through a container `Node2D` the way
`test_station_laser_phase.gd:43-50` does. It also silently prewarms 48 bullets per `before_each`
across both files (~21 station instantiations in the suite) — worth a sanity check on suite runtime.

### C4. The watch-it-fail plan does not account for GUT silently dropping an unloadable script.

`3-plan.md:266-272` says steps 1 and 4 "land their tests before their implementation". `BACKLOG.md`
*Discovered* records that when `test_space_station.gd` referenced classes that did not exist yet,
GUT printed `---- All tests passed! ----`, reported the wrong script count and **exited 0**; the
parse errors were on stderr only, and `/agent/verify.sh` step 3 checks neither. A test file
referencing `RadialAttackPattern` or `StationGunnery` before those `class_name`s exist is precisely
that case. Spell out that the red must be read off **stderr** (or by asserting GUT's script count),
not off GUT's verdict — otherwise the plan's own watch-it-fail step is the thing that silently
passes.

---

## Smaller notes

- **`AttackController` is at `global/components/attack_controller.gd`, not
  `assault/scenes/systems/attack_controller.gd`** (`1-context.md:40,56`, and `3-plan.md:155` repeats
  the framing). The rejection conclusion still stands — the pool-container argument and "cannot stop
  a dead turret without freeing someone else's child" are both real — but one of its stated reasons
  is wrong: `attack_controller.gd:24-30` is not a `Timer`, it is a float accumulator that does
  `_timer -= pattern.fire_interval` specifically to *preserve* overshoot, so four of them would not
  "independently drift". Correct the reasoning so the next person does not inherit a false belief
  about a shared component.

- **"the phases are mutually exclusive"** (`3-plan.md:87`) is not quite true for pool sizing. Turret
  bullets live ~4.1 s and the first ring lands 2.0 s after `armor_broken`, so the real peak is
  ~27 leftovers + 10 = ~37, not `max(27, 23)`. Still under 48, so the number survives — but fix the
  sentence, since the derivation is going into a code comment for the next tuner.

- **"nearest node in group `player`"** (`3-plan.md:56`) — `aimed_attack_pattern.gd:24-26` and
  `gatling_attack_pattern.gd:29-31` both take `players[0]`, not the nearest. Match the shipped
  behaviour (there is only ever one player) rather than implementing a different thing the plan's
  own "exactly as `AimedAttackPattern` does" clause promises.

- **Test 14's "wait one frame"** (`3-plan.md:255-257`): the station's `queue_free()` → pool
  `_exit_tree()` → per-bullet `queue_free()` chain spans the delete-queue flush. It probably resolves
  in one flush, but assert it rather than assume — two `process_frame` awaits cost nothing and this
  is the test that guards `ENEMIES_CLEARED`.

- **Scope.** 8 + 17 = 25 tests, plus a new resource, a new node, 10 config exports, a scene edit and
  four doc updates. Sub-item 3 was 16 tests and took a full session with three review rounds. This is
  at or slightly over one session. Candidates to drop without losing coverage: integration 8
  (the layer assertion is a re-read of two scene files, and `3-plan.md:107-115` already establishes
  there is no self-damage mechanism to regress), integration 16 (the config-copy discipline is
  already pinned by `test_station_laser_phase.gd`), and integration 4 (subsumed by 3 and 9).

- **Backlog done-condition.** `BACKLOG.md` sub-item 4 says "a headless run of the section produces no
  errors". Nothing in the test plan runs the station firing inside a `LevelDirector` section, and
  `/agent/verify.sh` step 2 boots the project but never plays Level 1. Either add a cheap check or
  restate the 4a done-condition explicitly when you split the backlog item — and if you do add a
  director test, obey the coroutine-leak rule in `tests/README.md:41-50` (`_wait_enemies_cleared()`
  polls at 1 s; a test returning while it is suspended leaks and the gate stays green).

- **New `ext_resource` UIDs.** Hand-editing `space_station.tscn` to add the `Gunnery` node (and, per
  B1, the `BulletPool` node with `enemy_bullet.tscn`) means hand-writing `uid://` values.
  `tests/integration/test_resource_uid_integrity.gd` will catch a mismatch — take the UIDs from the
  sibling `.gd.uid` / the target's own header rather than inventing them.

## Research check

Verified by fetching the sources, not taken on trust:

- **Finding 4 is fully supported.** Sparen A3 does say "you typically need at least three bullets per
  ring", does say the changing angle "has been adjusted so that the angle does not divide nicely into
  360 degrees", does give "1.5 degrees per ring", and does frame it as "avoiding the creation of
  blind spots". The research is accurate; the plan is what fails to apply it (B2).
- **Findings 1 and 2 are supported, but mis-attributed.** "Good for pressure, allows conscious
  manipulation by the player" / "Good for creating obstacles" and the chunking quote are **Boghog's**,
  not Sparen A2's. `2-research.md:9` lists Sparen A2 first. Sparen A2 does contain the ring quote used
  later ("By definition, most of the bullets in a ring will never come near the player") — that one is
  correct.
- **Finding 3's co-citation of Boghog is spurious.** `2-research.md:11` cites Boghog 101 alongside
  ResetEra for "bullets are meant to be slower than the player"; Boghog discusses bullet speed only in
  relation to travel distance and visual perception, never against ship speed. The 70–90 % figure
  therefore rests on a single forum summary. Low impact — the plan's actual numbers are derived from
  measured repo constants (player 400 px/s at `move_state.gd:21` ✓, gunship 260 at
  `gunship_config.tres:13` ✓, interceptor 220 at `interceptor_config.gd:12` ✓) — but drop the
  unsupported citation.
- Tradeoffs are present and non-token throughout, including one recorded against the plan's own choice
  (`2-research.md:41-46`, most ring bullets never reach the player). Good.

## Verified correct, for the record

- `bullet_pool.gd:40` really is `get_parent().get_parent()` with no export; the rotation hazard the
  plan describes is real (`station_laser_phase.gd:123` rotates the station, and the turrets sit under
  a `Turrets` node that rotates with it).
- No self-damage analogue: `enemy_bullet.tscn` HitBox is layer 256 / mask 128; `space_station.tscn`
  core HurtBox is layer 512 / mask 1121 (= 97 | 1024), which excludes 256. The `hit_mask_override = 128`
  rule from sub-item 3 (`BACKLOG.md` *Discovered*) genuinely has no counterpart here, in either
  direction. (`3-plan.md:233` says "neither bit 256 nor bit 8" — the "bit 8" clause is meaningless;
  drop it.)
- Turret geometry: `space_station.tscn` places turrets at `(±76, ±76)`, `station_turret.tscn` uses a
  `CircleShape2D` radius 26, so `spawn_radius = 26` and the rotation-invariance claim both check out.
- Barrel aim: `ENEMY.md:59-63` and `BACKLOG.md` *Discovered* both record barrels pointing at −Y with
  `rotation = 0`. `global_rotation = dir.angle() + PI/2` maps local −Y onto `dir` (DOWN → `PI`), and
  test 6 really does fail today by 180°.
- `_ready()` ordering: `turret_root` is `@onready` (`space_station.gd:38`), so it is null during the
  gunnery's `_ready()`. Resolving turrets lazily per volley is correct.
- The process-wide-config trap is handled the way `station_laser_phase.gd:50-69` handles it.
- `push_warning` is not a GUT failure (`tests/README.md:85`), so unit test 8's premise holds.
- Arena bounds x ∈ [−164, 1444], y ∈ [−444, 1164] (`enemy_bullet.gd:12-16`) and the station at world
  (640, 180) (`level_1_director.gd:225-227`) — the pool-size arithmetic reproduces.
- Adding children to `SpaceStation` does not disturb `space_station.gd:76-79`'s
  `for child in get_children(): if child is HitBox` loop, since `BaseEnemy._add_contact_hitbox()`
  (`base_enemy.gd:48-59`) has already appended the HitBox by then.
- Idle pooled bullets are physically inert: `bullet_pool.gd:47-48` sets
  `process_mode = PROCESS_MODE_DISABLED`, and `CollisionObject2D`'s default disable mode removes them
  from the physics server, so 48 prewarmed bullets parked at the station centre cannot touch the player.

## What would make this APPROVED

B1 (pool parenting — prefer authoring the `BulletPool` in `space_station.tscn`), B2 (a step value
with a ratio far from a small rational, and a test 12 that goes red on `0.21`), C1 (move the pattern
test to `integration/`), C2 (state and test the `ship.rotation` question), C3 (container-parent
`test_space_station.gd`), C4 (read the red off stderr). The smaller notes are corrections to text
and can ride along.

---

## Round 2

VERDICT: APPROVED

All six round-1 findings are resolved in substance, not just acknowledged. I re-derived the two
blockers from the code and the arithmetic rather than reading the plan's account of them, and B1's
replacement design is now verified end-to-end on this engine build. Findings below name what I
checked.

### B1 — resolved, and I verified the replacement design actually runs

`3-plan.md:99-134` replaces `_station.add_child(_pool)` with a `BulletPool` authored in
`space_station.tscn` as a direct child of `SpaceStation`, found from `StationGunnery` via
`@export var bullet_pool: BulletPool` with a `get_parent().get_node_or_null("BulletPool")` fallback.

Checked, in this order:

- `global/components/bullet_pool.gd:47` really is `_container = get_parent().get_parent()` with no
  export, so `pool → SpaceStation → enemy_container` is the only placement that resolves to world
  space. (Both this plan and round 1 cite this as `bullet_pool.gd:40`; the line is **47**.)
- `space_station.tscn:57-103`: `SpaceStation` is a `CharacterBody2D` whose direct children are
  `Sprite2D`, `CollisionShape2D`, `HurtBox`, `Health`, `HitFlashAnimationPlayer`, `Turrets` (`:88`)
  and `LaserPhase` (`:102`). Two more siblings fit cleanly.
- `@export var bullet_pool: BulletPool` is not a new idea in this repo — `attack_controller.gd:10`
  declares exactly that field, and `level_1.tscn:24-26` / `light_assault_ship.tscn:99-101` show the
  working text-format wiring.
- **Ran it.** I built a throwaway scene with the plan's exact shape (`CharacterBody2D` root, a
  `BulletPool` node with `bullet_scene`/`pool_size` set in the scene, and a sibling node carrying
  `node_paths=PackedStringArray("bullet_pool")` + `bullet_pool = NodePath("../BulletPool")`),
  instanced it into a container inside a live frame on Godot v4.6.3.stable.official.7d41c59c4:

  ```
  [Gunnery] _ready: bullet_pool = BulletPool:<Node#…>   is BulletPool? true
  pool._container == container? true   idle=6
  ```

  The export is resolved **before** the consumer's `_ready()` (Godot applies deferred node-path
  properties at the end of `SceneState::instantiate()`), and the pool resolves the container
  correctly. Scratch files removed; the working tree is clean.
- I also re-ran the station with a code-added-but-pre-tree pool from a real frame: `_container ==
  container`, prewarm ran, `acquire()` reparented into `EnemyContainer`, and the station's children
  came out as `… Turrets, LaserPhase, BulletPool, @Area2D@28 (the contact HitBox)` — so
  `space_station.gd:76-79`'s `for child in get_children(): if child is HitBox … break` still finds
  the HitBox that `BaseEnemy._add_contact_hitbox()` appends during `super._ready()`
  (`space_station.gd:50`). No interference.
- Blast radius on existing consumers: only `test_space_station.gd:22` and
  `test_station_laser_phase.gd:29` instance the scene live; `test_station_assault_section.gd:210`
  only reads the wave resource, so it needs no fix. `test_station_laser_phase.gd:42-51` already
  routes through a container, so it resolves correctly with the pool added.
- Test 2 (`3-plan.md:346-349`) now asserts the pool **exists** among `station.get_children()`, that
  the gunnery's reference points at that node, and that it is not under `Gunnery`/`LaserPhase`/
  `Turrets` — it fails if the pool is missing entirely, which is what round 1 asked for.

### B2 — resolved; I recomputed the numbers independently and they are exactly right

Computed `fmod(k * step, TAU/10)` for `k = 1..20`, sorted, largest gap **including the wrap gap**:

| step | largest gap | as % of spacing | vs `0.25 × spacing` = 0.15708 |
|---|---|---|---|
| `0.24` | 0.05664 rad | 9.01 % | passes, 2.77× margin |
| `0.21` | 0.19991 rad | 31.8 % | **fails** |

That matches `3-plan.md:214-217` and `3-plan.md:370-376` to three decimals, including the "~2.8×
margin" claim. The golden-angle derivation also checks: `TAU/10 × 0.381966 = 0.239996`, and
`spacing/step = 2.6180`. Rewritten test 11 therefore goes red on the rejected value and green on the
shipped one, which is the evidence round 1 demanded. The vacuous `fmod`-tolerance assertion is gone.

Non-blocking sharpening in the notes below (the 0.25 threshold, and where the test must read the
step from).

### C1 — resolved

`3-plan.md:300-308` moves the pattern file to `tests/integration/test_radial_attack_pattern.gd` and
quotes the rule correctly: `tests/README.md:16` reserves `unit/` for "One file per autoload or
`global/components/` component. No scene loading." Consistent with `test_space_station.gd:12-13` and
`test_station_laser_phase.gd:25-26`.

### C2 — resolved, and the reason is real

`3-plan.md:76-91` makes "ignores `ship.rotation`" a stated contract with a one-line reason in the
resource header. Verified the divergence exists (`aimed_attack_pattern.gd:31`,
`gatling_attack_pattern.gd:35`, both `Vector2.DOWN.rotated(ship.rotation)` — the plan cites the
aimed one as `:29`, actual `:31`) and that it would matter: `station_laser_phase.gd:123` does
`_station.rotation += rotation_speed * delta` with `rotation_speed` = 0.5 from
`space_station_config.gd:46`, so one 2.0 s `core_ring_interval` is 1.0 rad of hull rotation against
a 0.628 rad spacing. Pattern test 6 (`3-plan.md:322-325`) pins the contract, and the gunnery ring
tests set `LaserPhase.rotation_speed = 0.0` first — a technique that really is in the suite already
(`test_station_laser_phase.gd:286`; the plan cites `:283-284`). Test 10 is also re-specified as an
**absolute**-angle assertion, closing the vacuous-pass hole round 1 identified.

### C3 — resolved

Build step 7 (`3-plan.md:279-286`) routes `test_space_station.gd` through a container `Node2D`.
Confirmed `test_space_station.gd:28-30` is the bare `add_child_autofree(_station)`, and that
`get_parent` / `get_child_count` appear nowhere else in that file (only line 30 uses `add_child`),
so the fixture change cannot break its existing assertions.

### C4 — resolved

`3-plan.md:394-410`. `BACKLOG.md:317` confirms the failure mode verbatim (GUT printed
`---- All tests passed! ----`, reported `Scripts 2` instead of 3, exit 0), and `/agent/verify.sh:14`'s
FATAL regex matches none of it. The plan now requires the red to be read off stderr or off GUT's
script count, and — better — names two reds that need no such trick: test 6 (barrels, fails today by
~180°, and `BACKLOG.md:410-411` confirms all four turret instances are at `rotation = 0` with
barrels at −Y) and test 2 (seen red by temporarily misparenting the pool).

### Smaller notes from round 1 — all carried

- `AttackController` path corrected (`1-context.md:40`, `3-plan.md:237`) and the false "independently
  drift" claim explicitly withdrawn in both (`1-context.md:61-65`, `3-plan.md:241-245`). Verified
  `attack_controller.gd:24-30` is the `_timer -= pattern.fire_interval` accumulator.
- Pool sizing corrected to the ~37 handover peak (`3-plan.md:140-143`). Reproduced: 12 bullets /
  1.8 s = 6.7/s; `enemy_bullet.gd:12-16` gives y_bottom 1164, so ~984 px at 240 px/s = 4.1 s → ~27;
  ring 10 / 2.0 s at 210 px/s over ~4.7 s → ~23; 27 + 10 = 37 < 48.
- `players[0]` matched to the shipped behaviour (`3-plan.md:72-74`); actual lines are
  `aimed_attack_pattern.gd:22-24` and `gatling_attack_pattern.gd:29-31`.
- Two `process_frame` awaits in the teardown test (`3-plan.md:380-384`).
- Backlog done-condition restated and the director-level check explicitly moved to 4b, with the
  `tests/README.md:41-50` coroutine-leak rule flagged for then (`3-plan.md:427-434`).
- UID guidance (`3-plan.md:273-276`): `global/components/bullet_pool.gd.uid` really is
  `uid://kvgsxhn0cac7` and `enemy_bullet.tscn:1` really declares `uid://wi7ci5dkn7k7`.
- The meaningless "bit 8" clause is gone with the cut layer test.
- `2-research.md:138` re-attributes findings 1/2 to Boghog; `2-research.md:140` drops the
  unsupported Boghog co-citation on bullet speed and labels ResetEra as a single source.

### Fresh pass against the standard rejection criteria

- **No reinvention.** `global/resources/attack/` holds only `forward`, `aimed` and `gatling`; none
  emits more than one bullet and none has an arc. `RadialAttackPattern` subclasses the existing
  `fire(ship, pool)` seam (`attack_pattern_resource.gd:15`) and keeps runtime state on the node, as
  `attack_pattern_resource.gd:1-5` requires.
- **Conventions.** Composition ✓ (a sibling node of `LaserPhase`; `space_station.gd` gains only a
  `turrets()` data accessor). Config-driven ✓ (10 exports on `SpaceStationConfig`, copied into node
  fields in `_ready()` exactly as `station_laser_phase.gd:93-99` does, with deliberately different
  node defaults so test 15 is not vacuous). Scene geometry as node exports, mirroring
  `emitter_radius` (`station_laser_phase.gd:48`) ✓. No `WORLD_SCALE` multiplication inside the scene
  (`3-plan.md:219-221`) ✓. No `randf()` ✓.
- **The tests can fail.** Test 6 fails against shipped code today. Test 11 fails on `0.21`
  (recomputed above). Pattern test 3 is a real `arc / (count - 1)` division-by-zero boundary; test 1's
  wrap-gap assertion is the one that catches a seam duplicate; test 9 is the exhaustion path
  (`bullet_pool.gd:63-66` returns null after a `push_warning`, and `tests/README.md:85` confirms
  `push_warning` is not a GUT failure). Test 4 asserts bullet *origins*, not just a count.
- **Alternatives.** `call_deferred`, `container_override`, two resources, a downward arc, per-turret
  pools, survivor escalation and `AttackController` are all weighed with reasons. The one omission I
  can think of — create the pool inside `space_station.gd._ready()`, which is legal (a node may add
  children to itself, as `interceptor.gd:30-34` does) — loses to the scene version on the plan's own
  composition rule and is no simpler, so its absence is not a defect.
- **Research.** Tradeoffs are present per finding, including one recorded against the plan's own
  choice (`2-research.md:146-151`), and the two mis-citations round 1 found are fixed.
- **Scope.** Still the borderline. Round 1 measured 25 tests; the revised list is
  9 + 16 = **25** (see nit 1), so the two cuts were offset by the C2-mandated additions. I am not
  blocking on it, because the plan is unusually prescriptive (every test has its assertion spelled
  out) and steps 1-5 are small files. If the session runs long, cut in this order and say so in
  `5-progress.md`: gunnery test 16 (`the timers actually run`), gunnery test 14 (determinism — no
  `randf()` is a code-review property here), pattern test 8 (damage/speed, subsumed by the fan and
  ring tests). Do **not** cut tests 2, 6, 11 or 13 — those are the four that pin the design.

## Non-blocking (do these while implementing; none of them justified another round)

1. **The test count is wrong.** `3-plan.md:292` says "Two files, 23 tests"; the lists enumerate 9 +
   16 = 25. Fix the number, or actually make the cuts.
2. **The scene edit needs `node_paths=`, and omitting it fails silently.** The text scene format
   only resolves an exported Node reference when the node tag declares it. I verified both sides on
   4.6.3: with `node_paths` the export is live before `_ready()`; **without** it, the property is
   left `null`, *no error is printed and the gate stays green* — only the plan's fallback saves it.
   Write it exactly as `level_1.tscn:24-26` does:

   ```
   [node name="Gunnery" type="Node2D" parent="." node_paths=PackedStringArray("bullet_pool")]
   script = ExtResource("8_ss")
   bullet_pool = NodePath("../BulletPool")
   ```
3. **Test 11 must read `core_ring_step` and `core_ring_count` off the gunnery node** (i.e. the values
   copied from the shipped `.tres`), never from literals. With literals it locks nothing and the
   round-1 finding comes straight back.
4. **Test 11's `0.25 × spacing` threshold catches re-tread periods 2, 3 and 4 but not 5+**
   (`step = spacing/5 = 0.1257` re-treads five lanes forever yet leaves a 20 % gap and would pass).
   That is a defensible line — five lanes at 7.2° is not the blind spot three lanes at 31° is — but
   say so in the test comment so the next reader knows the bound is deliberate, not incidental.
5. **Build step 4 runs before step 5, so the `Gunnery` node's script does not exist yet.** New
   scripts have no `.gd.uid` until an import pass generates one. Either write step 5 before step 4,
   or run `godot --headless --path . --import` in between and copy the minted UID. Omitting the
   `uid=` attribute entirely is also legal — `test_resource_uid_integrity.gd:56-57` only checks the
   *pairing* — and I confirmed a `uid`-less `[ext_resource type="Script" path="…"]` loads fine.
6. **`1-context.md:107-109` still carries the refuted design**: "The gunnery node therefore creates
   the pool and adds it to its *parent*." That is the exact sentence B1 killed, and it now
   contradicts `3-plan.md:99-134`. Rewrite that paragraph when you touch the docs.
7. **`b1check.gd` is committed at the repo root** (from cycle `c364899`) — a scratch `SceneTree`
   script. Delete it. Worth knowing *why* its output is misleading: it does its `add_child` calls
   inside `_initialize()`, where `root.is_node_ready()` is **false**, so `_propagate_ready()` never
   reaches the subtree and the pool reports `_container = <null>, idle = 0` no matter how it is
   parented. Re-run from the first `_process()` frame and the same code prints
   `_container == container? true, idle = 8`. It is a harness artifact, not evidence against the
   design — do not let it re-open B1.
8. **Line-citation drift**, inherited from round 1 and worth fixing in the code comments the plan
   says will quote them: `bullet_pool.gd:40` → **:47**; `aimed_attack_pattern.gd:24-26` → **:22-24**;
   `aimed_attack_pattern.gd:29` → **:31**; `test_station_laser_phase.gd:283-284` → **:286**.
   (`gatling_attack_pattern.gd:29-31,35`, `station_laser_phase.gd:104,123`, `attack_controller.gd:24-30`
   and `interceptor.gd:36` are all correct as cited.)
