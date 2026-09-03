# Station bullet-hell fire (EPIC sub-item 4a)

> **Revised after review round 1** (`4-review.md`). Six changes: the `BulletPool` is now authored
> in `space_station.tscn` instead of added from code (B1 — the original design is refused by the
> engine, reproduced twice); `core_ring_step` is now `0.24` with a golden-angle derivation and a
> test that actually goes red on the old value (B2); the pattern test moves to `integration/`
> (C1); `RadialAttackPattern`'s relationship to `ship.rotation` is now stated and tested (C2);
> `test_space_station.gd` gets a container parent (C3); the watch-it-fail step now reads red off
> stderr (C4). Two tests were cut for scope and several text errors corrected.

## Problem

Today the first half of the Level 1 mini-boss fight is **completely passive**. The station spawns,
sits at world y 52–308, and four turrets wait to be shot. Nothing shoots back until the last turret
dies, at which point the laser phase (sub-item 3) wakes up. So the fight the player actually meets
is: thirty seconds of target practice, then a real boss.

After this change:

- While the turrets live, each one **fires an aimed 3-bullet fan** on a shared volley cadence.
  Killing a turret visibly and immediately removes one gun from the volley — the reward loop that
  the armour rule was built to teach now has teeth, because the armour is also the *threat*.
- Once the armour breaks, the core starts firing **precessing full rings** of bullets that
  interleave with the sweeping laser beams, so phase 2 is a bullet-hell phase rather than a laser
  phase.
- Turret barrels **point at the player** while firing, instead of pointing at the top of the screen
  (the open *Discovered* item in `BACKLOG.md`).

Out of the original sub-item 4, reinforcement waves are **deferred to sub-item 4b** — see
`1-context.md` for the split and for the `waves_complete` hazard 4b has to solve.

## Design

### One new node: `StationGunnery` (`station_gunnery.gd`), a `Node2D` child of `space_station.tscn`

Modelled line-for-line on `StationLaserPhase`, which is the shipped precedent for "a phase of this
boss is a child node": resolve `get_parent() as SpaceStation` with a `push_warning` bail, copy the
config into own fields in `_ready()`, connect `armor_broken` and `died`, tear down on death, and
expose `live_*()` accessors for tests. `space_station.gd` gains **no** gun logic (one public
accessor only, below).

Responsibilities:

- Drives the `BulletPool` authored beside it in the scene (see below) — it does **not** create one.
- Phase 1 — a `Timer` at `turret_fire_interval`. Every tick, **every live turret** fires one aimed
  fan. All live turrets fire on the same tick: research finding 2 (chunking) says a legible volley
  beats four independently drifting cadences, and it makes "one fewer gun" instantly readable.
- Phase 2 — on `armor_broken`, stop the turret timer and start a ring timer at
  `core_ring_interval`. Each tick the core fires one full ring, and the ring's base angle
  **precesses** by `core_ring_step`.
- On `died`, stop both timers. In-flight bullets are freed by `BulletPool._exit_tree()`.

### One new shared resource: `RadialAttackPattern` (`global/resources/attack/`)

`extends AttackPatternResource`, so it plugs into the existing `fire(ship, pool)` seam that
`AimedAttackPattern` and `GatlingAttackPattern` already use. It generalises *both* shapes this
feature needs, which is why it is one resource and not two:

| Field | Meaning |
|---|---|
| `bullet_count: int = 10` | Bullets per shot. |
| `arc: float = TAU` | `>= TAU` → a full ring, spacing `TAU / count`, no duplicate at the seam. `< TAU` → a fan of that angular width **centred** on the base direction, spacing `arc / (count - 1)`. |
| `base_angle: float = 0.0` | Base direction in radians, **absolute in world space**. Written by the caller between shots to precess a ring — see the note on runtime state below. |
| `aim_at_player: bool = false` | When true, `base_angle` is added to the angle toward `get_nodes_in_group("player")[0]`, falling back to `Vector2.DOWN` when there is no player. |
| `bullet_damage: int` / `bullet_speed: float` | Written onto the acquired bullet's `HitBox` and `speed`, same as the shipped patterns. |
| `spawn_radius: float = 0.0` | Each bullet spawns this far from the ship **along its own angle**, so a ring emerges from the hull rim and a fan emerges from the barrel mouth instead of from the entity's centre. |

Turret fan = `count 3, arc 0.35, aim_at_player true, spawn_radius 26`.
Core ring = `count 10, arc TAU, aim_at_player false, spawn_radius 130`, `base_angle` advanced by
the gunnery each shot.

**It takes `players[0]`, not the nearest player.** That is what `aimed_attack_pattern.gd:24-26` and
`gatling_attack_pattern.gd:29-31` both do, and there is only ever one player. Matching the shipped
behaviour beats inventing a different one.

#### `RadialAttackPattern` deliberately IGNORES `ship.rotation` (review C2)

Both shipped patterns fold the ship's rotation into their non-aimed branch
(`aimed_attack_pattern.gd:29`, `gatling_attack_pattern.gd:35`, both
`Vector2.DOWN.rotated(ship.rotation)`). **This one must not**, and the divergence has to be a
stated contract rather than an accident, because an implementer copying the shipped patterns would
ship a completely different attack:

`StationLaserPhase._physics_process` rotates the hull at `laser_rotation_speed` (0.5 rad/s) during
**exactly** the phase the ring fires in. Over the 2.0 s `core_ring_interval` that is 1.0 rad of hull
rotation against a 0.628 rad ring spacing — so folding in `ship.rotation` would add an uncontrolled
~1.6-spacings-per-ring drift on top of the designed `core_ring_step`, and the precession would no
longer be the property `core_ring_step` is tuned for or that the design-lock test checks.

So `base_angle` is absolute world-space, the gunnery owns the only precession, and a one-line
comment in the resource header says why it differs from its two siblings.

**Runtime state stays in the node, not the resource.** `attack_pattern_resource.gd`'s header is
explicit that patterns are configuration only so that ships can share a `.tres`. The precession
counter therefore lives on `StationGunnery` (`_ring_angle`), which assigns `pattern.base_angle`
immediately before each `fire()`. The gunnery also builds its patterns with `.new()` and never
loads a shared `.tres` — the same thing `interceptor.gd:36` does.

### The `BulletPool` is authored in `space_station.tscn`, as a direct child of `SpaceStation`

**Round 1 of review killed the original design here, and it was right.** The plan previously had
`StationGunnery._ready()` call `_station.add_child(_pool)`. That is refused by the engine:
`Node::_propagate_ready()` increments `data.blocked` on the parent *before* readying its children,
and `Node::add_child()` fails hard on `data.blocked > 0`. Reproduced twice on this exact build
(Godot v4.6.3.stable.official.7d41c59c4), in the exact `Container → Station → Gunnery` shape:

```
ERROR: Parent node is busy setting up children, `add_child()` failed.
   at: add_child (scene/main/node.cpp:1709)
station children after: 1   # only the Gunnery — the pool was never added
```

The pool would have stayed orphaned outside the tree, `BulletPool._ready()` would never have run,
`_container` would never have resolved, and the first volley would have called `acquire()` on an
empty pool. **And the gate would not have caught it**: that message matches none of
`/agent/verify.sh`'s FATAL patterns. `StationLaserPhase` is not a precedent — `station_laser_phase.gd:104`
does `add_child(_volley_timer)` onto **itself**, whose `blocked` is back to 0 by the time its own
`NOTIFICATION_READY` arrives.

**So the pool is a node in the scene**, sibling to `Gunnery` and `LaserPhase`, with `bullet_scene`
and `pool_size` set in the scene file. `StationGunnery` finds it via
`@export var bullet_pool: BulletPool` wired in the scene, with a `get_parent().get_node_or_null("BulletPool")`
fallback and a `push_warning` bail if it is missing.

This is better than the code version on its own merits, not just because the code version is
illegal. `bullet_pool.gd:40` hardcodes its container as `get_parent().get_parent()`, so the pool
**must** be a direct child of the station: under the gunnery or a turret it would resolve to the
station itself, and since `StationLaserPhase._physics_process` rotates the hull, every in-flight
bullet would be a child of a rotating node and the whole bullet field would swing around with it.
Authoring the pool in the scene makes that constraint a **structural property of the scene file**
rather than a comment someone can violate later. Bullets then live in `enemy_container` in world
space, exactly like every other enemy's.

`docs/BULLET_POOL.md` documents this same contract and gains the station as a listed consumer.

`pool_size = 48`. Derivation: phase 1 peak is 4 turrets × 3 bullets per 1.8 s = 6.7 bullets/s; a
bullet expires at the arena bounds in `enemy_bullet.gd` (x ∈ [-164, 1444], y ∈ [-444, 1164]), and
from the station at world (640, 180) a downward bullet at 240 px/s covers the ~984 px to the bottom
bound in ~4.1 s → ~27 in flight. Phase 2 adds 10 per 2.0 s at 210 px/s → ~23 in flight.
**The phases overlap at the handover** (review note): turret bullets live ~4.1 s and the first ring
lands 2.0 s after `armor_broken`, so the real peak is ~27 leftover turret bullets + 10 ring bullets
≈ 37, not `max(27, 23)`. 48 still carries it, with ~11 of headroom. This derivation goes in a code
comment at the pool node's `pool_size`, corrected sentence included.

### Ordering trap: the gunnery's `_ready()` runs BEFORE the station's

Godot readies children before parents. `SpaceStation.turret_root` is `@onready`, so it is **still
null** while `StationGunnery._ready()` runs — unlike `config`, which is an `@export` initialised at
property-init time and is what `StationLaserPhase` gets away with reading. The gunnery therefore
resolves the turret list **lazily, on every volley**, never in `_ready()`. That is also what makes
dead turrets drop out for free.

`SpaceStation` gains one public accessor, `turrets() -> Array[StationTurret]`, returning the
existing private `_turrets()`. Data access, not gun logic; `live_turret_count()` is left exactly as
it is because its behaviour is pinned by `test_space_station.gd`.

### Turret barrels aim

The turret sprite's barrels point along local **−Y**. Before firing, the gunnery sets
`turret.global_rotation = dir.angle() + PI / 2`, which maps local −Y onto the aim direction
(`dir = DOWN` → `global_rotation = PI`). `global_rotation`, not `rotation`, so it stays correct if
the hull is ever rotating. This is free of gameplay side-effects because the turret's HurtBox is a
**`CircleShape2D` of radius 26** (`station_turret.tscn`) — rotation-invariant. Radius 26 is also
where `spawn_radius` for the fan comes from: the muzzle sits on the hurtbox rim.

### No self-damage risk, in either direction

`enemy_bullet.tscn`'s `HitBox` is layer 256 / mask **128** — the player hurtbox only — and the
station's core HurtBox mask is `97 | 1024` = 1121, which excludes 256. So the `hit_mask_override`
dance phase 2's beams need has no analogue here, in either direction: the station's own beams are
overridden to mask 128, so they cannot shoot down its own bullets either.

This is recorded in `ENEMY.md` rather than pinned by a test. Review round 1's scope note is
accepted: the assertion would be a re-read of two scene files, and there is no mechanism here that
could regress it — unlike the beams, where `LaserRay`'s *default* mask is the hazard.

### Tuning, and where each number comes from

New exports on `SpaceStationConfig`, applied in `StationGunnery._ready()`:

| Export | Value | Justification |
|---|---|---|
| `turret_fire_interval` | `1.8` | 4 turrets × 3 bullets = 12 per volley; research finding 2 says a chunk needs a longer interval than a stray. Gives 6.7 bullets/s at full strength, decaying to 1.7 with one gun left. |
| `turret_burst_count` | `3` | The smallest chunk that reads as a line rather than a stray (finding 2). |
| `turret_burst_arc` | `0.35` (≈20°) | Wide enough that strafing does not dodge all three, narrow enough to read as one fan. |
| `turret_bullet_damage` | `12` | Between the interceptor's 4 and the gunship's 15; four turrets firing at once must not out-damage the 40 contact hit. |
| `turret_bullet_speed` | `240.0` | 60 % of the player's 400 px/s top speed, inside the shipped 220–260 band and the 70–90 % benchmark (finding 3). |
| `core_ring_interval` | `2.0` | Ten bullets per ring; 5 bullets/s. Runs *alongside* the 6.5 s laser cycle, so the combined phase-2 attack changes every ~2 s, well inside the 5–10 s switch cadence (finding 5). |
| `core_ring_count` | `10` | ≥3 (finding 4). Spacing `TAU/10` = 36°; at 300 px from the hull that is a ~188 px gap, dodgeable at 400 px/s. |
| `core_ring_step` | **`0.24`** rad (≈13.75°) | See the derivation below — this value was `0.21` and was **wrong**. |
| `core_bullet_damage` | `10` | Ring bullets are unavoidable-by-position, so they hit softer than the aimed fan. |
| `core_bullet_speed` | `210.0` | 52 % of player speed — the slowest of the three, because phase 2 already has sweeping beams to dodge. |

#### `core_ring_step`: why `0.21` was wrong and `0.24` is right (review B2)

Research finding 4 (Sparen A3, verified verbatim by the reviewer) requires a per-ring step that does
**not** re-tread earlier rings' radial lanes, or the pattern leaves a permanent safe lane. The
previous value `0.21` failed exactly that test while *citing* it as justification:

- spacing = `TAU / 10` = 0.6283185 rad
- `3 × 0.21 = 0.63` → ring 4 lands **0.0017 rad (0.096°)** off ring 1's lanes — about **0.5 px** at
  the 300 px radius used for the gap arithmetic
- so the ring collapses onto **three** lanes and stays there: over a whole phase (~20 rings) the
  total drift is ~0.010 rad ≈ 3 px

The ratio 2.992 was quoted in the old plan as proof the step "does not divide evenly". It is the
opposite: being *almost exactly* 3 is the defect. (The supporting clause "0.21 is not a rational
fraction of TAU" was not an argument — no float is.)

**New value: `core_ring_step = 0.24`**, from the golden-angle relation
`spacing × 0.381966 = 0.6283185 × 0.381966 ≈ 0.24`, i.e. a step-to-spacing ratio of **2.618** (φ+1).
The golden ratio is the irrational least well approximated by small rationals, which is precisely
the "maximal lane coverage per ring, no lane ever re-tread" property finding 4 asks for. Measured
over 20 rings (more than a 40–50 s phase fires at a 2 s cadence), the lane offsets
`k × step mod spacing` cover the spacing interval with a **largest gap of 0.057 rad = 9.0 % of the
spacing**; the old `0.21` leaves a largest gap of **~0.20 rad = 31 % of the spacing**. The
derivation goes in the `.tres` comment.

`spawn_radius` values (26 turret, 130 core) are **scene geometry, not stats**, so they are exports
on `StationGunnery`, exactly as `emitter_radius` is on `StationLaserPhase`. Everything here is in
final on-screen pixels at `scale = 1` and is **not** multiplied by `ArenaCamera.WORLD_SCALE`.

Density numbers are derived from this project's measured constants, not from an external figure —
Sparen A4 explicitly refuses to give a threshold. Labelled a judgement call, per the skill.

### Phase-transition timing, deliberately

- The **first turret volley lands one full interval (1.8 s) after spawn**, not on spawn: the timer
  simply starts in `_ready()` and nothing fires immediately. That is the grace period for the
  player to register the boss, and it needs no extra `start_delay` field.
- The **first ring lands one interval (2.0 s) after `armor_broken`**, not immediately.
  `StationLaserPhase._on_armor_broken()` already fires its first beam volley on that same frame;
  stacking a ring on top of it would spike the phase change instead of introducing it.

### Alternatives rejected

- **Reuse `AttackController` per turret.** It lives at `global/components/attack_controller.gd`
  (not `assault/scenes/systems/`, as `1-context.md` said — corrected there too). It drives one
  pattern for one ship (`_ship = get_parent()`) and would have to be parented onto turrets the
  gunnery does not own, with no way to stop a dead turret firing without freeing someone else's
  child, and no way to make four guns fire as one legible volley. **Correction from review:** the
  old reasoning also claimed four controllers would "independently drift". They would not —
  `attack_controller.gd:24-30` is a float accumulator that does `_timer -= pattern.fire_interval`
  specifically to preserve overshoot. The rejection stands on the ownership and volley-legibility
  arguments alone; the drift claim was false and is withdrawn so nobody inherits it.
- **Creating the `BulletPool` from `StationGunnery._ready()`.** Illegal — the engine refuses it, see
  above. `call_deferred` would work but leaves the "must be a direct child of the station"
  constraint enforced only by a comment.
- **A `container_override` export on `BulletPool`.** Would let the pool sit under the gunnery. It
  changes a shared component used by five other ships for no benefit that authoring the pool in the
  scene does not already give.
- **Two pattern resources (`SpreadAttackPattern` + `RingAttackPattern`).** The ring is the `arc >=
  TAU` case of the fan; two resources would duplicate the acquire/damage/speed body already
  duplicated three times across the shipped patterns.
- **A downward arc instead of a full ring for the core.** Doubles pressure per bullet (Sparen: most
  ring bullets never come near the player) but reads as a nozzle rather than a fortress, and swings
  off-screen as the hull rotates. Tradeoff recorded in `2-research.md`.
- **Survivor turrets firing faster as their siblings die.** Rejected in `2-research.md` Q4: it
  would cancel out the only feedback the player gets for shooting the guns.
- **Per-turret bullet pools.** Four pools of 15 pre-allocates more, and each one resolves its
  container to the rotating `Turrets` node.

## Build sequence

1. **`RadialAttackPattern`** — `global/resources/attack/radial_attack_pattern.gd`. Write
   `tests/integration/test_radial_attack_pattern.gd` first and watch it fail **on stderr** (see the
   watch-it-fail note below).
2. **`SpaceStation.turrets()`** public accessor — one method, no behaviour change.
3. **Config exports** — ten fields on `space_station_config.gd` + values in
   `space_station_config.tres`.
4. **Scene edit** — add a `BulletPool` node and a `Gunnery` node to `space_station.tscn`, both
   direct children of `SpaceStation`, and wire the gunnery's `bullet_pool` export to the pool.
   New `ext_resource` entries take their `uid://` values **from the targets themselves** —
   `global/components/bullet_pool.gd.uid` is `uid://kvgsxhn0cac7` and
   `enemy_bullet.tscn`'s header declares `uid://wi7ci5dkn7k7`. Do not invent UIDs;
   `tests/integration/test_resource_uid_integrity.gd` will fail on a mismatch.
5. **`StationGunnery`** — `station_gunnery.gd`.
6. **`tests/integration/test_station_gunnery.gd`.**
7. **`test_space_station.gd` container fix** (review C3) — `test_space_station.gd:28-30` does
   `add_child_autofree(_station)` with no container, so once a `BulletPool` is a child of the
   station, `bullet_pool.gd:40`'s `get_parent().get_parent()` resolves to **GUT's own parent of the
   test script**. Nothing fires there today (that file has no `await`s, so no volley reaches 1.8 s),
   so it is latent rather than live — but the plan names this resolution as the load-bearing hazard
   of the feature and must not leave a known-wrong instance of it in the suite. Route it through a
   container `Node2D` the way `test_station_laser_phase.gd:43-50` does. Also sanity-check suite
   runtime: the pool prewarms 48 bullets per station instantiation, across ~21 instantiations.
8. Gate, then docs (`ENEMY.md`, `docs/BULLET_POOL.md`, `docs/architecture/modules/global.md` for
   the new shared resource, `PROJECT.md`), `BACKLOG.md` split + tick.

## Test plan

Two files, 25 tests (9 + 16 as enumerated below — the "23" this line carried was a stale count,
review non-blocking item 1). As built it is 26: `test_radial_attack_pattern.gd` gained an 11th
case, `test_a_zero_bullet_count_fires_nothing`, recorded in `5-progress.md`.

Every assertion below is one that can actually go red.

**Scope discipline (review):** two tests from the previous draft are cut rather than carried. The
station-bullets-cannot-hit-the-station layer assertion is gone (it re-reads two scene files and has
no mechanism that could regress it — recorded in `ENEMY.md` instead), and the separate
"all turrets dead → turret volley fires nothing" boundary is folded into test 12 below, which
covers the same path.

### `tests/integration/test_radial_attack_pattern.gd` — pure geometry, no station

**In `integration/`, not `unit/`** (review C1): it loads `enemy_bullet.tscn` and needs a live tree,
and `tests/README.md:16` reserves `unit/` for "one file per autoload or `global/components/`
component. No scene loading." Both existing station test files place themselves in `integration/`
for exactly this reason.

Uses a bare `Node2D` ship and a `BulletPool` wired to `enemy_bullet.tscn` inside a two-deep
container so the pool's `get_parent().get_parent()` resolves.

1. `test_a_full_ring_is_evenly_spaced` — `count 10, arc TAU`: 10 bullets, sorted directions have
   consecutive gaps of `TAU/10 ± 0.001`, **and the last-to-first wrap gap is also `TAU/10`** (this
   is the assertion that fails if the seam is duplicated by using `arc/(count-1)` for rings).
2. `test_an_arc_is_centred_on_the_base_angle` — `count 3, arc 0.35, base_angle 0`: directions are
   `-0.175, 0, +0.175`.
3. `test_a_single_bullet_arc_does_not_divide_by_zero` — **boundary.** `count 1, arc 0.35`: exactly
   one bullet, on `base_angle`, and no engine error (GUT fails the test on one). Naive
   `arc / (count - 1)` divides by zero here.
4. `test_aim_at_player_offsets_the_base_angle_toward_the_player` — a stub `Node2D` in group
   `player` placed at a known off-axis position; the centre bullet points at it within 0.01 rad.
5. `test_aim_at_player_falls_back_to_down_with_no_player` — **boundary**, matches
   `AimedAttackPattern`'s shipped fallback.
6. `test_the_pattern_ignores_ship_rotation` — **review C2, and the one that pins the divergence
   from the two shipped patterns.** Fire a non-aimed ring, record the directions, set
   `ship.rotation = 1.0`, fire again: the direction sets are identical. Goes red the moment someone
   "fixes" the resource to match `aimed_attack_pattern.gd:29`.
7. `test_spawn_radius_places_each_bullet_on_its_own_angle` — `spawn_radius 130`: every bullet is
   130 ± 0.5 px from the ship, and each one's offset direction equals its travel direction.
8. `test_damage_and_speed_are_written_onto_the_bullet` — `HitBox.damage` and `speed` match.
9. `test_it_returns_quietly_when_the_pool_is_exhausted` — **boundary.** Pool of 2, ring of 10: 2
   bullets, no crash. (`BulletPool.acquire` `push_warning`s, which GUT does not treat as a failure.)

### `tests/integration/test_station_gunnery.gd`

Station instanced into a container `Node2D` owned by `add_child_autofree`, per the
`ExplosionEffect` trap in `tests/README.md`. Timings are overridden **on the gunnery node**, never
through `config` — the process-wide-resource trap. Volleys are driven by calling the gunnery's fire
methods directly rather than by awaiting timers, so the tests are deterministic and fast; one test
exercises the timers themselves.

**All ring tests set `LaserPhase.rotation_speed = 0.0` first** (review C2), the technique
`test_station_laser_phase.gd:283-284` already uses. Without it the hull rotates under the ring
between frames and every absolute-angle assertion becomes timing-dependent.

1. `test_nothing_is_fired_before_the_first_volley` — right after `_ready()`, zero bullets in the
   container. Fails if anything fires on spawn.
2. `test_the_pool_is_a_direct_child_of_the_station` — **the B1 regression test, and it must fail if
   the pool is missing entirely, not merely misplaced.** Asserts a `BulletPool` exists among
   `station.get_children()`, that the gunnery's `bullet_pool` reference points at *that* node, and
   that it is not a descendant of `Gunnery`, `LaserPhase` or `Turrets`.
3. `test_a_volley_fires_one_fan_per_live_turret` — one forced volley → `4 × 3 = 12` bullets.
4. `test_destroying_turrets_removes_their_guns` — **the headline test.** Kill 2 of 4, force a
   volley → exactly 6 bullets, and they originate from the two *surviving* turret positions
   (asserted by proximity to those positions, so a version that fired 6 bullets from the wrong guns
   still fails).
5. `test_turret_bullets_are_aimed_at_the_player` — stub player off-axis; each fan's centre bullet
   points at it and the outer two straddle it by `± arc/2`.
6. `test_turret_barrels_face_the_player_when_firing` — for each live turret, local −Y rotated by
   `global_rotation` equals the direction to the player within 0.01 rad. Closes the *Discovered*
   item; fails today by ~180°.
7. `test_bullets_live_in_the_enemy_container_not_in_the_station` — every fired bullet's parent is
   the station's parent. The regression test for the rotation trap.
8. `test_the_core_does_not_fire_until_the_armor_breaks` — before: `is_core_firing()` false and a
   forced ring produces nothing. After killing all four turrets: `is_core_firing()` true.
9. `test_a_core_ring_is_a_full_evenly_spaced_ring` — 10 bullets, gaps `TAU/10`, all `130 ± 0.5` px
   from the station centre.
10. `test_successive_rings_precess_by_the_configured_step` — with `rotation_speed = 0`, two forced
    rings; ring 2's angles are ring 1's plus `core_ring_step`, mod `TAU`. Asserted as **absolute**
    angles against a known `_ring_angle`, so it cannot pass vacuously the way the previous draft's
    version could.
11. `test_the_ring_step_leaves_no_permanent_safe_lane` — **the design lock, rewritten so it goes
    red on the old value** (review B2). Over `k = 1..20` rings, compute the lane offsets
    `fposmod(k * core_ring_step, spacing)` where `spacing = TAU / core_ring_count`, sort them, and
    assert the **largest gap** (including the wrap-around gap) is `< 0.25 * spacing`. Shipped
    `0.24` gives a largest gap of ~0.057 rad (9.0 % of spacing) and passes with ~2.8× margin; the
    rejected `0.21` gives ~0.20 rad (31 %) and **fails**. This is the evidence the lock is real —
    the previous draft's `fmod` assertion cleared its own tolerance by 0.0017 and green-lit `0.21`.
12. `test_turret_fire_stops_when_the_armor_breaks` — after `armor_broken`, the turret timer is
    stopped **and** a forced turret volley produces zero bullets (this second half absorbs the cut
    "all turrets dead" boundary test).
13. `test_everything_stops_and_bullets_are_freed_when_the_station_dies` — fire a volley, kill the
    core, then `await` **two** `process_frame`s (the `queue_free()` → `_exit_tree()` →
    per-bullet `queue_free()` chain spans the delete-queue flush; assert it rather than assume one
    flush is enough). Both timers stopped, no `EnemyBullet` left in the container. This is what
    stops dead-boss bullets holding `ENEMIES_CLEARED` open.
14. `test_volleys_are_deterministic` — two forced volleys with the player unmoved produce identical
    direction sets. Fails the moment anyone reaches for `randf()`.
15. `test_config_values_are_copied_onto_the_gunnery` — the node's fields equal the shipped `.tres`
    values. Not vacuous: the node's own defaults are deliberately different (a conservative
    single-bullet, slow, low-damage fallback), and the test also asserts `config` itself is
    unchanged afterwards.
16. `test_the_timers_actually_run` — one timing test, not fifteen: set `turret_fire_interval` to
    0.2 on the node, `await` ~0.5 s, assert at least one volley landed. Everything else is forced.

### Watch-it-fail plan — read the red off stderr, not off GUT (review C4)

`BACKLOG.md` *Discovered* records that when `test_space_station.gd` referenced classes that did not
exist yet, **GUT printed `---- All tests passed! ----`, reported the wrong script count, and exited
0** — the parse errors went to stderr only, and `/agent/verify.sh` step 3 checks neither signal. A
test file referencing `RadialAttackPattern` or `StationGunnery` before those `class_name`s exist is
*exactly* that case, so the naive "watch it fail" step would itself silently pass.

Therefore, at steps 1 and 5, the red is confirmed by **either** an explicit parse error on stderr
**or** GUT's reported script count being lower than the number of files in `tests/` — never by
GUT's pass/fail verdict alone.

Two reds are available without any such trick, and both must be observed:
- Test 6 (barrels face the player) fails today by ~180°, against shipped code.
- Test 2 (pool parentage) must be seen red by temporarily parenting the pool under `Gunnery` in the
  scene before the final commit — that check is the only thing standing between this design and a
  silently rotating bullet field.

## Risks

| Risk | Check |
|---|---|
| Pool exhaustion at 48 (fires `push_warning`, bullets silently missing) | Pattern test 9 pins the graceful path; the corrected ~37-at-handover derivation is in the code comment so the next tuner recomputes it |
| Phase 2 too dense: 10 bullets/2 s **plus** two sweeping beams on a stage-1 mini-boss | Numbers are all `.tres` knobs; `core_ring_interval` is the single dial, documented in `ENEMY.md`. Genuinely unverifiable headless — flagged as needing a play test |
| Phase 2 has **no aimed component**, so research finding 1 says a safe spot is possible | Mitigated by three moving layers (hull rotates, ring precesses on a golden-angle step, beams sweep); gunnery test 11 is the lock on the precession half. Recorded in `ENEMY.md` as the thing to re-check if the phase reads as safe-spottable |
| `_ready()` ordering: reading `_station.turret_root` before the station readies | Designed out — turrets are resolved lazily per volley. Test 3 would fail immediately if this regressed |
| Adding a pool child changes what `get_parent().get_parent()` means for existing station tests | Build step 7 fixes `test_space_station.gd`; gunnery test 2 pins the parentage |
| Bullets holding `ENEMIES_CLEARED` open after the boss dies | Test 13 |
| Config mutation leaking across the suite | Overrides applied to the node only; test 15 asserts `config` is unchanged |
| Hand-edited `ext_resource` UIDs in `space_station.tscn` | UIDs copied from the targets (build step 4); `test_resource_uid_integrity.gd` is the backstop |

## Out of scope

- **Reinforcement waves from three screen edges** — sub-item 4b, split out in `BACKLOG.md`.
  Note that the backlog's original done-condition for sub-item 4 ("a headless run of the section
  produces no errors") is **not** met by this plan: nothing here runs the station firing inside a
  live `LevelDirector` section, and `/agent/verify.sh` step 2 boots the project but never plays
  Level 1. When the backlog item is split, 4a's done-condition is restated explicitly as the two
  test files below, and the director-level check moves to 4b — where it can cover reinforcements
  and station fire together, and where the `_wait_enemies_cleared()` coroutine-leak rule in
  `tests/README.md:41-50` will apply.
- Turret scoring, the opaque `station_core.png` background, the `Gunship` `collision_damage` bug,
  and the `base_enemy` hitbox-scale bug — all open *Discovered* items, none touched here.
- Any new art. Bullets reuse `enemy_bullet.tscn`'s existing `Line2D` visual.
- Sub-item 5's death sequence and handoff.
