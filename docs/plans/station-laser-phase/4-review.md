VERDICT: CHANGES_REQUESTED

# Review — Station laser phase (EPIC sub-item 3)

Reviewed `1-context.md`, `2-research.md`, `3-plan.md` against the actual code. Every claim below
was checked by reading the named file, and the four numbered findings were additionally
**reproduced at runtime** on this machine (Godot v4.6.3.stable) with throwaway scripts that were
deleted afterwards.

The shape of the change is right: a `StationLaserPhase` child node, an `armor_broken` signal on
the station, timings in the `.tres`, deterministic volley angles, reuse of `LaserRay`. Nothing is
reinvented from `global/components/`, and the design-space/screen-pixel distinction is handled
correctly. But two of the plan's own done-condition tests **cannot fail as specified**, and the
headline timing arithmetic is wrong. Fix 1–4, then this is approvable.

---

## Blocking

### 1. The time-to-lethal formula is wrong; `warn_duration = 1.2` does not give 1.96 s

`3-plan.md:100` and `2-research.md` Q1 both use `0.2 s (laser_init) + warn_duration + 0.56 s
(laser_increase)`. That double-counts the init frame.

`laser_ray.gd:155-161` — `start()` plays `laser_init` **and** creates the
`get_tree().create_timer(warn_duration)` in the same call. The timer runs *concurrently* with the
0.2 s init animation, and `_on_animation_finished` (`laser_ray.gd:177-181`) deliberately does
nothing when `warn_duration > 0`. So the init frame is inside the warn window, not before it.

Measured (`warn_duration` → ms until `is_lethal_now()`):

| warn | measured | plan's formula |
|---|---|---|
| 0.0 | 697 ms | 760 ms |
| 0.5 | 1062 ms | 1260 ms |
| **1.2** | **1766 ms** | 1960 ms |
| 3.0 | 3567 ms | 3760 ms |

The real relation is `warn_duration + ~0.56 s`. So the chosen 1.2 gives **1.77 s** to lethal, and
the stated justification — "landing on the Danmakufu figure almost exactly" (`2-research.md`, Q1)
— does not hold. Either set `laser_warn_duration = 1.4` (⇒ ~1.96 s) or restate the target honestly.

Same section, second error: the dissolve is **0.84 s**, not "~0.3 s" (`3-plan.md:102`).
`laser_ray.tscn:153-155` — `laser_dissolve` is 7 frames × `duration 0.6` at `speed 5.0` =
7 × 0.12 s. Measured full beam lifetime at warn 1.2 / active 2.0: **4513 ms**, not the plan's
~4.3 s. `laser_volley_interval = 6.0` survives this (≈1.5 s of clear screen instead of 1.7), but
the numbers in the table must be corrected or the next reader will re-derive them wrong.

### 2. Test 6 — the regression test for the whole design — passes with the fix reverted

`3-plan.md:211` specifies "let a volley go fully lethal for ≥ 0.5 s with all turrets dead" and
expects a reverted `hit_mask_override` to drop the station 600 → 0. With
`emitter_radius = 140` and `_VOLLEY_ANGLES[0] = 0.0` (`3-plan.md:126`), **it does not.**

Reproduced, station un-armoured, default mask (896), beam at radius 140:

```
SELFKILL angle=0.000 r=140 mask=0   -> station_alive=true  hp=600
SELFKILL angle=0.785 r=140 mask=0   -> station_alive=false hp=-1     ([Health] took 9999: 600 → 0)
SELFKILL angle=0.785 r=140 mask=128 -> station_alive=true  hp=600
```

Why: `_build_collision()` (`laser_ray.gd:147-152`) puts the HitZone rect at local
`(0, length*0.5)`, so the beam occupies local y `140 → 1676`, while the core HurtBox
(`space_station.tscn:74-76`, 240×240) ends at y = 120. Twenty pixels of clearance on the axes.
On the **diagonals**, `Vector2(0, 140).rotated(PI*0.25) = (-99, 99)` is *inside* the ±120 square,
so those beams do overlap and do kill.

Volley 0 fires at angles `0.0` and `0.0 + PI` — both axis-aligned, both safe. Test 6 as written is
vacuous. It must force a diagonal volley (`_VOLLEY_ANGLES` index 2 or 3, or seed the volley
counter) and say in a comment why.

This also corrects `3-plan.md:110`: "140 px puts the emitter 20 px outside the 240 px hull's flat
edge" is true only for the flat edges. The hull half-diagonal is ~170 px, so on two of the four
volley angles the emitter sits ~30 px **inside** the hull. That is not a reason to change the
radius — it is precisely what makes `hit_mask_override` load-bearing — but the plan currently
states the opposite of the measured geometry.

### 3. Test 3 (`test_armor_broken_emits_exactly_once`) cannot fail either

`3-plan.md:208` proposes killing all 4 turrets, then emitting `received_damage` at the dead
turrets 3 more times, and claims that without `_armor_broken` "the phase restarts".

`station_turret.gd:45-47` — `_on_received_damage` returns immediately when `not _alive`. The
emit never reaches `Health.decrease`, so `health_component.gd:40-42`'s 0 → 0 re-emit never
happens, `_on_health_changed` never runs (`station_turret.gd:54-56` guards again), and `destroyed`
is never re-emitted. The trap the plan cites is already closed one level down — which is exactly
what `tests/integration/test_space_station.gd:102-110`
(`test_destroyed_turret_ignores_further_damage`) already pins. So `armor_broken` cannot double-fire
through that path, with or without the guard.

Make it a real boundary test by driving the station's own handler:
`t.destroyed.emit(t)` on already-dead turrets. That does re-enter the station's subscription and
does fail without `_armor_broken`. Alternatively drop the test and demote the guard's rationale
from "not decorative" (`3-plan.md:52-54`) to "defence in depth" — the current justification is
factually wrong.

### 4. `tests/unit/test_laser_ray_hit_mask.gd` breaks the suite layout rule

`3-plan.md:180` and test 11 (`:216`) put the `LaserRay` mask test in `tests/unit/`.
`tests/README.md:16` — "`unit/` | One file per autoload or `global/components/` component. **No
scene loading.**" `LaserRay._ready()` requires `$BeamSprite` and `$HitZone`
(`laser_ray.gd:79-81`), so the test has to instance `laser_ray.tscn`. This is the same reason
`tests/integration/test_space_station.gd:12-13` gives for living in `integration/`. Move it.

---

## Non-blocking, but fix while implementing

### 5. `hit_mask_override` must be set **before** `add_child()` — say so

`laser_ray.gd:103` reads the export inside `_ready()`, which `add_child()` runs synchronously. The
plan's rejection of the post-`add_child` assignment (`3-plan.md:88-94`) argues the export removes
order-dependence; it does not, it inverts it. The export is still the better call (declarative,
assertable, additive, `0` preserves today's 896 exactly — verified), but the plan should state the
ordering requirement and the doc comment should too.

Related: `3-plan.md:139-141` shows `laser.position` / `laser.rotation` with no ordering relative
to `add_child()` / `start()`. `LaserRay.auto_start` defaults to **true** (`laser_ray.gd:38`), so
an `add_child()` before those assignments telegraphs a frame at the parent origin with rotation 0.
Follow the shipped sequence in `level_1_director.gd:159-165`: `auto_start = false` → set exports →
`add_child` → set transform → `start()`.

### 6. Angle assertions need tolerances

`Node2D.rotation` is float32-backed: setting `PI * 1.25` reads back `3.92699074745178` against a
`3.92699081698724` literal. Test 9's "the two beams are `PI` apart" (`3-plan.md:214`) must use
`assert_almost_eq` or `angle_difference`, not `assert_eq`. Test 8's tolerance is already stated.

### 7. Rotation side-effects the risk table does not name

`3-plan.md:224` covers the contact `HitBox`. Two more, both cosmetic/intended but worth one line
in `ENEMY.md` so the next reader is not surprised:

- The four turret **wrecks** rotate with the hull. `ENEMY.md:54-56` records that all turrets are
  authored at `rotation = 0` with barrels pointing −Y; after this change they spin.
- The core **HurtBox** is a 240×240 square, so at 45° its corners reach ~34 px beyond the
  axis-aligned footprint. `ENEMY.md:91-102`'s collision table currently reads as if it were static.

Checked and clear: nothing else writes the station's `rotation`. The station wave has no `.move()`
(`level_1_director.gd:239`), so `WaveManager._spawn_ship` attaches no `EnemyPathMover`
(`wave_manager.gd:193-196`), and `_spawn_ship` never sets rotation itself. `ArenaCamera` is
unaffected. Beams parented inside the station cannot block `ENEMIES_CLEARED`, which polls
`container.get_child_count()` (`level_director.gd:105-118`).

### 8. Leftover spikes are still in the repo and tracked

`1-context.md` says the spikes were "deleted afterwards". They are not:
`git ls-files spike/` returns `spike/test_spike_laser.gd`, `spike/test_spike_selfkill.gd` and both
`.uid` files. They sit outside `-gdir=res://tests` so the gate does not run them, but they are dead
code against the exact scripts this item changes. Delete them in step 1 (or correct `1-context.md`).

### 9. Scope

4 code steps + 12 tests + the docs pass is at the upper bound of one session. Two easy trims that
lose no coverage: test 7 (`collision_mask == 128`) is a strictly cheaper subset of a fixed test 6
— keep both only if test 6 is repaired per finding 2; and test 11 *is* step 1's file, listed
twice. ~9 tests buys margin.

---

## Verified sound — recorded so it is not re-checked next cycle

- **The self-damage trap is real.** Core `HurtBox` is `collision_layer = 512`
  (`space_station.tscn:68-71`) and is deliberately kept live rather than disabled
  (`space_station.gd:6-11`, `ENEMY.md:76-87`). `LaserRay._on_area_entered`
  (`laser_ray.gd:246-254`) emits `received_damage` straight into it, bypassing the `HitBox` type
  filter. Reproduced above: 600 → 0 in one frame on a diagonal beam.
- **`@export_flags_2d_physics var hit_mask_override: int = 0` is valid on Godot 4.6.3** — loaded a
  script declaring it, default read back `0`, assignment of `128` round-tripped. It would be the
  first `@export_flags*` in this repo (`grep -rn 'export_flags' --include=*.gd` is otherwise empty).
  The `!= 0` sentinel is sound: mask 0 means "collide with nothing", which for a beam is
  indistinguishable from an inert beam, so it is not a configuration anyone would want. Keep the
  doc comment saying that.
- **`_HIT_MASK` really is 896** (`128|256|512`, `laser_ray.gd:68`) — read back off a live instance.
- **Player `HurtBox` is layer 128** (`player_fighter.tscn:334-335`), so `128` is the right override.
- **`const _VOLLEY_ANGLES: Array[float] = [...]` parses** on 4.6.3.
- `move_state.gd:21` — `max_move_speed = 400.0`. ✓
- `health_component.gd:40-42` — `set_health` emits `amount_changed` on every call, 0 → 0 included. ✓
- `base_enemy.gd:65-73` — `died.emit()` then `queue_free()` in the same call. ✓ And `died` is
  declared *and* emitted with zero arguments, so the teardown hook does **not** hit the
  zero-parameter-signal trap that `Health.amount_changed` does (`tests/README.md:81-84`).
  `StationTurret.destroyed(turret)` is 1-arg declared and 1-arg emitted — handler takes one. ✓
- `emitter_radius` correctly kept out of the `.tres` and out of `WORLD_SCALE`: everything inside
  `space_station.tscn` is authored in final screen pixels (`ENEMY.md:27-32`), and only the spawn
  offset `at(0, -90)` is scaled (`wave_manager.gd:172`). ✓ Config-driven timings in
  `SpaceStationConfig` match the `CLAUDE.md` rule and the existing `turret_health` precedent
  (`space_station_config.gd:15`, `space_station_config.tres:11`). ✓
- Composition rule respected; nothing here duplicates a `global/components/` component.
- Research is honestly sourced: it carries a tradeoff column, records the three sources that turned
  out empty so they are not re-fetched, and labels Q2 (`0.5 rad/s`) as derived rather than sourced.
  Finding 3 (ULTRAKILL, a first-person game with a 1.0 s sweep) is used only for "constant angular
  velocity", which is a fair narrow borrowing.
- The GUT tests as described are writable: `spike/test_spike_laser.gd` and
  `spike/test_spike_selfkill.gd` already demonstrate `wait_seconds`, real physics stepping against a
  layer-128 stub `HurtBox`, and `add_child_autofree` on the station scene — modulo findings 2, 3, 4
  and 6.

---

VERDICT: CHANGES_REQUESTED

# Review round 2 — revision 1 of `3-plan.md`

All four round-1 blocking findings are **genuinely fixed**, and I re-measured the numbers rather
than taking the revision on trust. The design is settled; I have no further objection to the shape
of the change, the trigger, the mask export, the angle list, the rotation, or the teardown.

What holds this back is narrower than round 1: **two defects in the test-harness specification**
that will bite during unattended implementation — one that corrupts a globally-shared resource
across the suite, one that makes a named assertion wrong. Both are single-paragraph edits to the
plan and need no new research. Round 3 should be quick.

## Round-1 findings — re-verified as fixed

### Finding 1 (timing) — fixed, with one number still slightly optimistic

Measured on Godot 4.6.3, shipped values (`warn 1.4 / active 2.0`):

```
warn=1.40 active=2.00 -> lethal_ms=1891  full_lifetime_ms=4727
```

- **(a) Does 1.4 land near 1.96 s?** Near, not exactly. Measured **1891 ms**, not the 1966 ms the
  plan extrapolates at `3-plan.md:153`. The residual is the `laser_increase` animation measuring
  0.49–0.57 s run to run (process-frame granularity), not an error in the corrected
  `warn + 0.56` relation, which is right. 1.4 is the correct choice and lands in the 1.9–2.0 s
  band. **Nit:** restate as "≈1.9–2.0 s (measured 1891 ms)" rather than "≈1.96 s", so the next
  person to re-derive this does not find a third wrong number.
- **(a) Is 6.5 enough headroom?** Yes. Measured lifetime **4727 ms** against the plan's stated
  ~4.8 s, leaving **1.77 s** of clear screen — matching `3-plan.md:155`'s "~1.7 s" and inside
  finding 4's 5–10 s cadence. The dissolve correction to 0.84 s is right.
- `1-context.md` spike 1 and `2-research.md` Q1 no longer carry the double-counted formula. ✓

### Finding 2 (vacuous test 6) — fixed, and the fix is robust

**(b) Does `_volley_index = 2` really select a diagonal?** Yes, and better than the plan claims —
computed against the real ±120 hurtbox half-extent:

```
idx 0 angle=0.000 emitter=(0.0,140.0)   inside=false | opposed=(0.0,-140.0)  inside=false
idx 1 angle=1.571 emitter=(-140.0,0.0)  inside=false | opposed=(140.0,0.0)   inside=false
idx 2 angle=0.785 emitter=(-99.0,99.0)  inside=true  | opposed=(99.0,-99.0)  inside=true
idx 3 angle=2.356 emitter=(-99.0,-99.0) inside=true  | opposed=(99.0,99.0)   inside=true
```

Index 2 puts **both** beams of the volley inside the hull, so the regression bites twice over. And
because indices **2 and 3 are both diagonal**, an off-by-one in whether the counter is
read-then-incremented or incremented-then-read cannot silently disarm the test. Worth one line in
the plan: the counter must be *read for the current volley then incremented*, and either index
works. The honest angle-dependent geometry at `3-plan.md:87-104`, the rejected per-angle standoff
(`:106-112`, `:254`), and the "if the emitter ever moves outside the hull, only the mask assertion
still bites" docstring note all check out.

**(b) Is a test-settable `_volley_index` test-only API leaking into production?** No. It is a plain
internal `var`, not an `@export`, not a public setter. GDScript has no access modifiers, so a test
writing `phase._volley_index = 2` adds **zero** production surface — unlike a `set_volley_index()`
or an exported field, which would. This is the right call; no change needed.

### Finding 3 (test 3) — fixed, and it can now genuinely fail

**(c)** Yes. `turret.destroyed.emit(turret)` bypasses `station_turret.gd:45-47`'s `_alive` early
return entirely and lands directly on the station's subscription, where `live_turret_count()` is
already 0. Without `_armor_broken`, that re-enters the emit and the count goes to 4. With it, 1.
The test discriminates the guard, which the round-0 version could not.

The corrected rationale at `3-plan.md:62-70` is accurate: the `Health` 0→0 claim is retracted and
`test_space_station.gd:102-110` is correctly named as already pinning that path. **One nit:** the
"a fifth turret added to the scene and killed after the count already hit zero" example is
unreachable — a live fifth turret means the count was never 0. Drop it, or replace it with the
scenario that *is* reachable: a future repairable/respawning turret driving the count 0 → 1 → 0.
The other justification (re-emit from a future caller) is sound and is what the test exercises.

### Finding 4 (test placement) — fixed

`tests/integration/test_laser_ray_hit_mask.gd` (`3-plan.md:264-266`, `:283-285`), with
`tests/README.md:16` cited as the reason. ✓ Non-blocking 5–9 are all folded in correctly: the
"set before `add_child()`" requirement appears in both the prose (`:139-140`) and the proposed doc
comment (`:118-119`); the full shipped spawn sequence is spelled out (`:196-206`) with the
`auto_start` default correctly named as the reason; test 8 specifies `assert_almost_eq` /
`angle_difference` with the float32 example (`:305`); the three rotation side-effects are named and
routed to `ENEMY.md` (`:223-227`, `:277-279`); the `spike/` deletion is step 1 (`:267-269`).

---

## (d) Newly wrong in revision 1 — two blocking, three nits

### D1 (blocking) — `SpaceStationConfig` is a single shared instance; the test plan mutates it

`3-plan.md:288-290` — "Tests shorten the timings **on the instance** before the phase starts
(`warn 0.2 / active 0.3 / interval 1.0`); the shipped values are asserted separately against the
`.tres` in test 10." Combined with the spawn snippet at `:196-206`, which reads
`cfg.laser_warn_duration` **at spawn time**, the only way to shorten the timings is to write to
`station.config` — and that object is global. Measured:

```
config a==b instance?  true    a==preload?  true
mutating a.config -> b.config.turret_health=7   preload=120
```

`space_station.gd:24` is `@export var config = load("res://…space_station_config.tres")`, the scene
stores no override, and `ResourceLoader` caches — so **every station in the process shares one
`SpaceStationConfig`, and it is the same object `preload` hands the tests.** Tests 1–9 would
permanently rewrite the shipped `.tres` values in memory, and **test 10 is the test that asserts
those values**; within a file GUT runs tests in declaration order, so test 10 asserts against the
values tests 1–9 just clobbered. That is a self-inflicted red gate at the very end of the session.

Fix — pick one and state it in the plan:
- **Preferred:** `StationLaserPhase` copies the five timings out of `config` into its own fields in
  `_ready()` — the same "`.tres` applied in `_ready()`" pattern `space_station.gd:37-45` already
  uses for `health.max_health` — and the spawn path reads the phase's fields, not `cfg`. Tests then
  override the *phase node's* fields and never touch the resource. This also matches the
  `CLAUDE.md` config-driven convention more exactly than reading through on every volley.
- Or: tests do `station.config = station.config.duplicate()` in `before_each` before any write.

### D2 (blocking) — the test timings invert the very invariant test 2 exists to check

Measured with the plan's own test values:

```
warn=0.20 active=0.30 -> lethal_ms=765  full_lifetime_ms=1904
```

A beam lives **1.9 s**, but the plan's test `interval` is **1.0 s**. So volley 2 spawns while
volley 1's two beams are still dissolving, and the phase node holds **4** `LaserRay` children, not
2. Test 2 (`3-plan.md:299`) asserts "after the first volley exactly `laser_beam_count` `LaserRay`
children exist" and is credited with catching "beam leakage across volleys"; the risk table
(`:317`) leans on the shipped `interval 6.5 > lifetime 4.8` relation. The test configuration
**breaks that relation**, so test 2 is either flaky (passes only if sampled before t=1.0) or
asserts something false.

Fix: keep `interval > lifetime` in the test config too — `warn 0.2 / active 0.3 / interval 2.5`
costs ~1.5 s more per test and restores the invariant. (Or state that test 2 samples strictly
inside the first volley window, but then it no longer catches cross-volley leakage and the claim
must be dropped.) The same overlap makes **test 8** ambiguous: with beams from volleys 0..3
co-existing, attributing a beam's `rotation` to its volley needs either the wider interval or a
record-at-spawn hook. The wider interval fixes both.

### D3 (nit) — step 2 is not independently testable as scoped

`3-plan.md:272` assigns "Tests 1–3" to step 2, but tests 1 and 2 assert `is_active()` and count
`LaserRay` children — API that does not exist until step 4. Since the risk table (`:320`) now
explicitly sells step independence ("a window that ends early leaves a working tree"), fix the
mapping: step 2 gets test 3 plus an `armor_broken`-only version of test 1's negative case; tests 1
and 2 move to step 4.

### D4 (nit) — citation off by two

`3-plan.md:236` cites `base_enemy.gd:4, :69` for "`died` is declared *and* emitted with zero
arguments". `:69` is the `print`; `died.emit()` is `:71`. The claim itself is correct and I
re-verified it.

### D5 (nit) — citation points past the data

`3-plan.md:155` cites `laser_ray.tscn:153-155` for "7 frames × 0.12 s". Those three lines are the
`loop` / `name` / `speed` keys; the seven `"duration": 0.6` entries are at ~`:131-152`. Cite the
block, or `:155` alone for `speed = 5.0`.

---

## Re-verified as still correct after the revision

`laser_ray.gd:68` `_HIT_MASK` = 896; `:38` `auto_start` default true; `:147-152` `_build_collision`;
`:155-161` `start()`; `:246-254` `_on_area_entered`. `space_station.tscn:68-71` core HurtBox layer
512. `station_turret.gd:45-47` early return. `test_space_station.gd:102-110`. `move_state.gd:21`
400 px/s. `tests/README.md:16` and `:81-84`. `level_1_director.gd:159-165` spawn sequence and
`:239` the no-`.move()` station wave. `wave_manager.gd:172` the `WORLD_SCALE` spawn scaling and
`:194-196` the `EnemyPathMover` guard. `level_director.gd:105-118` the child-count poll.
`ENEMY.md:27-32` screen-pixel authoring. `@export_flags_2d_physics` and
`const _VOLLEY_ANGLES: Array[float]` both parse on 4.6.3; still the first `@export_flags*` in the
repo. Segment length 1536 px vs the 1468.6 px screen diagonal. ✓

Nothing that was right in revision 0 was broken by revision 1.

## What round 3 needs

Only D1 and D2, plus the four nits (D3–D5, the 1.96→1.89 restatement, the unreachable
fifth-turret example). No new research, no design change. Fix those and this is approved.
