# Station laser phase (EPIC sub-item 3)

Builds on `1-context.md` (code survey + four measured spikes) and `2-research.md` (seven sourced
findings). Numbers below are traced to one or the other; anything derived rather than sourced is
labelled.

> **Revision 1 — after review round 1** (`4-review.md`). Four blocking defects fixed:
> **(1)** the time-to-lethal formula double-counted the 0.2 s `laser_init` frame — the real
> relation is `warn + 0.56 s`, so `laser_warn_duration` moves **1.2 → 1.4** and the dissolve is
> 0.84 s, not 0.3 s; **(2)** test 6, the headline regression test, was **vacuous** — at
> `emitter_radius = 140` a beam on volley 0's axis-aligned angles misses the core hurtbox by
> 20 px, so the self-kill only reproduces on the diagonals; **(3)** test 3's boundary case could
> not fail, because `StationTurret._alive` already closes the path it was probing; **(4)** the
> `LaserRay` mask test was placed in `tests/unit/`, which `tests/README.md:16` forbids for
> anything that loads a scene. Non-blocking findings 5–9 are folded in as well.

> **Revision 2 — after review round 2** (`4-review.md`). Round 2 confirmed all four round-1
> findings fixed, and raised two more, both in the test-harness spec: **(D1)** `SpaceStation.config`
> is a **process-wide shared resource** — `space_station.gd:24` `load()`s it and `ResourceLoader`
> caches, so revision 1's "shorten the timings on the instance" would have clobbered the shipped
> values that test 10 asserts, guaranteeing a red gate at the end of the session; the phase now
> **copies** the timings into its own fields in `_ready()` (§3a). **(D2)** the test `interval 1.0`
> was **shorter than the measured 1904 ms beam lifetime**, inverting the very `interval > lifetime`
> invariant test 2 exists to check; it is now 2.5. Nits D3–D5 and two restatements
> (1.96 → measured 1891 ms; the unreachable "fifth turret" example) are folded in.
>
> **This revision has NOT been reviewed.** The `feature-workflow` gate allows a maximum of two
> review rounds, and both are spent. See `STATUS.md` — the item is parked at stage 4.

## Problem

Today the space-station mini-boss is a static target. The player shoots four turrets, the core
un-armours, and then the player shoots the core while the station does nothing. There is no
reason to move, so the second half of the fight is a damage-race against a stationary box —
exactly the failure mode `2-research.md` finding 4 names ("spinning his wheels, constantly doing
the same thing over and over").

After this change: the moment the last turret dies, the station **starts rotating** and begins
firing **telegraphed beams** outward from its hull on a repeating cycle. The player must keep
moving to stay out of the sweep. Every beam shows a warning line for ~2 s before it can hurt
anything, so a death is always a read the player missed, never an ambush.

## Design

### Shape of the change

A new node, **`StationLaserPhase`** (`Node2D`), added as a child of `space_station.tscn`. It
owns the whole phase: the trigger, the rotation, the volley cycle, and the beams. `SpaceStation`
gains exactly one thing — an `armor_broken` signal — and no laser logic at all.

This follows `CLAUDE.md`'s composition rule: the station is already assembled from components
(`Health`, `HurtBox`, `HitBox`, `HitFlashAnimationPlayer`, `Turrets`), and the laser phase is one
more child rather than more methods on `space_station.gd`.

```
SpaceStation (CharacterBody2D)
├── Sprite2D / CollisionShape2D / HurtBox / Health / HitFlashAnimationPlayer
├── Turrets/ Turret0..3          (StationTurret)
└── LaserPhase (StationLaserPhase)   ← new
    └── <LaserRay instances, spawned per volley, self-freeing>
```

### 1. Trigger — `SpaceStation.armor_broken`

`SpaceStation` connects to every turret's existing `destroyed(turret)` signal in `_ready()` and,
when `live_turret_count()` reaches 0, emits a new zero-argument signal **`armor_broken`**, guarded
by a `_armor_broken: bool` so it fires exactly once.

Why a station-level signal rather than the phase node subscribing to the turrets directly: the
station already owns the armour rule (`is_armored()` / `live_turret_count()`), so the *transition*
is station-level knowledge. It also gives sub-item 4 ("escalating fire from the survivors") the
same hook without a second subscription fan-out. `StationTurret`'s own header already says the
`destroyed` signal exists "for sub-items 3 and 4" — this is the consumer it was written for.

**On the `_armor_broken` guard (corrected in revision 1).** Revision 0 justified it with the
`Health` 0 → 0 re-emit trap (`health_component.gd:40-42`). That justification was wrong:
`StationTurret._on_received_damage` returns early when `not _alive` (`station_turret.gd:45-47`),
so damage aimed at a dead turret never reaches `Health` at all, and
`test_space_station.gd:102-110` already pins that. The guard's real job is narrower and still
worth having: it makes `armor_broken` idempotent against **any** re-entry through `destroyed`
itself — a re-emit from a future caller, or a repairable/respawning turret driving the count
0 → 1 → 0. (Revision 1 gave "a fifth turret added to the scene and killed after the count already
hit zero" as the example; the reviewer pointed out it is unreachable — a live fifth turret means
the count was never 0.) Test 3 exercises exactly that path (`turret.destroyed.emit(turret)`
on an already-dead turret), which does fail without the guard.

`StationLaserPhase` finds its station with `get_parent() as SpaceStation` and connects to
`armor_broken`. If the parent is not a `SpaceStation` it disables itself and returns — a plain
`Node2D` dropped in the wrong place must not crash.

### 2. The self-destruct trap — beam hit mask

This is the single most important constraint, and it is measured, not theorised
(`1-context.md` spike 2, re-reproduced by the reviewer): `LaserRay._HIT_MASK` is
`128 | 256 | 512` (`laser_ray.gd:68`), and the station's core `HurtBox` is on **layer 512**
(`space_station.tscn:68-71`), deliberately kept live rather than disabled. `LaserRay._on_area_entered`
(`laser_ray.gd:246-254`) emits `received_damage` straight into it, bypassing the `HitBox` type
filter. A beam mounted on an un-armoured station on the default mask produced
`[Health] SpaceStation took 9999 damage: 600 → 0 HP` — the boss kills itself the instant its own
laser phase starts.

**The overlap is angle-dependent, and the plan must be honest about that.** `_build_collision()`
(`laser_ray.gd:147-152`) puts the HitZone rect at local `(0, length*0.5)`, so a beam at
`emitter_radius = 140` occupies local y `140 → 1676`. The core hurtbox is a 240×240 square, so it
ends at y = 120 on the axes — a 20 px miss — but its half-diagonal is ~170 px, and
`Vector2(0, 140).rotated(PI*0.25) = (-99, 99)` is comfortably *inside* the ±120 square. Reviewer's
measurement:

```
angle=0.000 r=140 mask=default -> station alive, hp=600
angle=0.785 r=140 mask=default -> station DEAD, 600 → 0
angle=0.785 r=140 mask=128     -> station alive, hp=600
```

So two of the four volley angles self-kill and two do not. Revision 0 claimed "140 px puts the
emitter 20 px outside the hull's flat edge", which is true only for the flat edges — on the
diagonals the emitter sits ~30 px *inside* the hull and the beam visibly cuts out through the rim.
That is accepted (a rotating superweapon firing through its own structure reads fine, and the beam
sprite starts as a thin line), and it is what keeps test 6 able to fail.

**Rejected here: fixing this with geometry.** A per-angle standoff (`half_size / max(|cos|,|sin|)
+ 20`) would put every emitter outside the hull and remove the overlap entirely. It is more code
for a cosmetic gain, and spike 3 already measured why it is the wrong primary defence: the margin
is ~10 px and moves with the hull size, the 56 px beam width and the emitter angle. Worse, it
would make test 6 unable to fail again. **If a future change ever moves the emitter outside the
hull on all angles, test 6 becomes vacuous and must be replaced by the mask assertion it now
carries** — that note goes in the test's docstring.

**Fix:** the phase's beams hit the player hurtbox layer (128) and nothing else. Implemented by
adding one additive export to `laser_ray.gd`:

```gdscript
## Overrides the default multi-layer hit mask when non-zero. Must be assigned BEFORE add_child(),
## because _ready() reads it. Used by emitters mounted ON an entity that would otherwise be inside
## their own beam — SpaceStation's laser phase sets 128 (player hurtbox only) so the boss does not
## kill itself with its own beam. 0 = "use the default", not "collide with nothing": a beam that
## collides with nothing is inert and is not a configuration anyone wants.
@export_flags_2d_physics var hit_mask_override: int = 0
```

and in `_ready()`:

```gdscript
_hit_zone.collision_mask = hit_mask_override if hit_mask_override != 0 else _HIT_MASK
```

The reviewer confirmed on Godot 4.6.3 that `@export_flags_2d_physics var x: int = 0` parses and
round-trips, and that the default really is 896. It would be the first `@export_flags*` in this
repo.

**Rejected alternative:** set `laser.hit_zone.collision_mask = 128` from the spawner *after*
`add_child()`. It works today and needs no shared-code change — but it is silently order-dependent,
and any future reordering inside `LaserRay._ready()` re-arms the suicide with no test failure to
show for it. The export inverts the ordering requirement rather than removing it (it must be set
*before* `add_child`), but it makes the requirement a declarative property of the beam, directly
assertable, and documented on the export itself. `LaserRay` already has the precedent for a
per-instance behavioural flag (`race_hazard`), and the change is purely additive: `0` keeps
today's 896 byte-for-byte, which a test pins.

### 3. Timings — in `SpaceStationConfig`, per the config-driven convention

Corrected in revision 1: `start()` plays `laser_init` **and** starts the warn timer in the same
call (`laser_ray.gd:155-161`), so the 0.2 s init frame runs *inside* the warn window.
**Time-to-lethal = `warn_duration + ~0.56 s`.**

| Field | Value | Where it comes from |
|---|---|---|
| `laser_warn_duration` | **1.4 s** | Research Q1. ⇒ **≈1.9–2.0 s** to lethal — **measured 1891 ms** at the shipped values, not the 1966 ms a linear extrapolation gives; the residual is `laser_increase` measuring 0.49–0.57 s run to run at process-frame granularity — the Danmakufu delay-laser figure (120 f = 2.0 s) for a screen-covering beam, and ~6× the 0.3 s reaction floor. Deliberately **not** the 3.0 s the level's static laser columns use: finding 4 caps the attack cycle at 5–10 s and 3.0 s does not fit twice. |
| `laser_active_duration` | **2.0 s** | The 120-frame Master Spark active window (finding 1). |
| `laser_volley_interval` | **6.5 s** | Volley start to volley start. **Measured** beam lifetime is **4727 ms** (`1.89 + 2.0 + 0.84`; the dissolve is 7 frames × 0.12 s — durations at `laser_ray.tscn:131-152`, `speed = 5.0` at `:155`), leaving **1.77 s** of clear screen. Inside finding 4's 5–10 s switch cadence. Revision 0's 6.0 was derived from a 0.3 s dissolve and would have left only 1.2 s. |
| `laser_rotation_speed` | **0.5 rad/s** (≈29°/s) | **Derived, not sourced** — research Q2. Constant angular velocity (finding 3, ULTRAKILL). Player top speed is 400 px/s (`move_state.gd:21`); at the ~400 px the player sits from the station the beam edge moves at `0.5 × 400 = 200 px/s`, half the player's top speed. One 2.0 s window sweeps ~57°. |
| `laser_beam_count` | **2** | Research Q4. Two opposed beams sweep the plane while always leaving two large clear quadrants — finding 6's requirement that a rotating beam's swept region not be the whole screen. |


### 3a. The config resource is a **single shared instance** — copy the timings, never mutate it

*Added in revision 2, from review round 2 finding D1.*

`space_station.gd:24` is `@export var config: SpaceStationConfig = load("res://…space_station_config.tres")`,
the scene stores no override, and `ResourceLoader` caches. The reviewer measured the consequence:

```
config a==b instance?  true    a==preload?  true
mutating a.config -> b.config.turret_health = 7   (preload still reports 120 only if untouched)
```

So **every `SpaceStation` in the process shares one `SpaceStationConfig`, and it is the same object
`preload` hands a test.** Revision 1's test plan said tests "shorten the timings on the instance",
and the spawn snippet read `cfg.laser_warn_duration` at spawn time — which means the only way to
shorten them was to write to the shared resource. Tests 1–9 would have permanently rewritten the
shipped values in memory, and **test 10 is the test that asserts those values**; GUT runs tests in
declaration order within a file, so test 10 would assert against values tests 1–9 had clobbered.
A guaranteed red gate at the end of the session.

**Fix (chosen): `StationLaserPhase` copies the five timings into its own fields in `_ready()`, and
every later read goes through the phase's fields, never through `config`.**

```gdscript
var warn_duration: float
var active_duration: float
var volley_interval: float
var rotation_speed: float
var beam_count: int

func _ready() -> void:
    _station = get_parent() as SpaceStation
    if _station == null:
        set_physics_process(false)
        return
    var cfg := _station.config
    if cfg != null:
        warn_duration   = cfg.laser_warn_duration
        active_duration = cfg.laser_active_duration
        volley_interval = cfg.laser_volley_interval
        rotation_speed  = cfg.laser_rotation_speed
        beam_count      = cfg.laser_beam_count
    _station.armor_broken.connect(_on_armor_broken)
```

This is the same "`.tres` applied in `_ready()`" pattern `space_station.gd:37-45` already uses for
`health.max_health` and the turret HP, so it matches the `CLAUDE.md` config-driven convention more
exactly than reading through the resource on every volley. Tests then override the **phase node's**
fields and never touch the resource at all.

**Node ordering note:** Godot readies children before parents, so `StationLaserPhase._ready()` runs
*before* `SpaceStation._ready()`. That is safe here because the phase reads `_station.config` — an
`@export` initialised at property-init time, before any `_ready()` — and not any value
`SpaceStation._ready()` derives from it. It is the same ordering `space_station.gd:37-45` already
relies on for the turrets. Do **not** move the copy to depend on station-derived state.

**Rejected alternative:** `station.config = station.config.duplicate()` in the tests' `before_each`.
It works, but it puts the burden on every future test author remembering an invisible rule, and it
leaves production code reading a mutable global on every volley. The copy-in-`_ready()` version
fixes the production smell and the test hazard at once.

`laser_emitter_radius` is **not** in the config: it is scene geometry, not a stat. It becomes an
`@export var emitter_radius: float = 140.0` on `StationLaserPhase`. Per `ENEMY.md:27-32` and
`1-context.md`, everything *inside* `space_station.tscn` is authored in **final on-screen pixels
at `scale = 1`** and must **not** be multiplied by `ArenaCamera.WORLD_SCALE`; only the spawn
offset `at(0, -90)` is scaled (`wave_manager.gd:172`).

`segment_count` stays at the scene default 12 (12 × 128 = 1536 px), which exceeds the 1470 px
screen diagonal, so a beam always runs off-screen from any emitter position.

### 4. Volley geometry — deterministic, never `randf()`

The backlog says the station fires "at varying positions" and the obvious implementation is
`randf()`. Finding 5 is explicit that this is the documented mistake: "Don't decide attack orders
based on randomness", with the worked failure of a boss that picks from N attacks at random and
cannot be balanced. It also makes the phase untestable — a test cannot assert anything about a
random angle.

Instead, a fixed local-space angle list on `StationLaserPhase`:

```gdscript
const _VOLLEY_ANGLES: Array[float] = [0.0, PI * 0.5, PI * 0.25, PI * 0.75]
```

Volley `k` spawns `laser_beam_count` beams at local angles
`_VOLLEY_ANGLES[k % _VOLLEY_ANGLES.size()] + i * TAU / laser_beam_count`. Because the station is
rotating continuously underneath, the *world* angle of every volley differs anyway; the list adds
a second, controlled axis of variation with a known value range — exactly finding 5's recommended
alternative to RNG.

The volley counter is a plain `int`, `@export`-free and with no public setter, but **settable from
tests** (`_volley_index`) so test 6 can force a diagonal volley without waiting out two full
cycles. GDScript has no access modifiers, so a test writing `phase._volley_index = 2` adds **zero**
production surface — the reviewer confirmed this is the right call over a `set_volley_index()`.
The counter is **read for the current volley, then incremented**. Indices **2 and 3 are both
diagonal**, so a read-vs-increment off-by-one cannot silently disarm test 6 (review round 2
measured both beams of volley index 2 as landing inside the hull: `(-99, 99)` and `(99, -99)`).

Per-beam spawn, following the shipped sequence in `level_1_director.gd:159-165` — the ordering
matters because `LaserRay.auto_start` defaults to **true** (`laser_ray.gd:38`), so an early
`add_child()` telegraphs a frame at the parent origin with rotation 0:

```gdscript
var laser := _LASER_SCENE.instantiate() as LaserRay
laser.auto_start        = false
laser.warn_duration     = warn_duration          # the phase node's own copy, never cfg.* (§3a)
laser.active_duration   = active_duration
laser.hit_mask_override = _PLAYER_HURTBOX_MASK      # 128 — must be set BEFORE add_child()
add_child(laser)                                     # _ready() runs here and reads the override
laser.position = Vector2(0.0, emitter_radius).rotated(angle)   # LaserRay extends along local +Y
laser.rotation = angle
laser.start()
```

### 5. Rotation

`StationLaserPhase._physics_process(delta)` does `_station.rotation += rotation_speed * delta` (the
phase node's own copy of the config value — see §3a)
while the phase is active, and nothing at all while it is not. Constant rate, no easing — finding
3's "constant angular velocity" is the property that makes a sweep predictable.

Beams are children of the phase node, which is a child of the station, so rotating the station
sweeps every live beam for free — spike 4 measured this (`st.rotation = PI/2` moved a beam's
`danger_rect()` from `(572, 480) 56×768` to `(-348, 272) 768×56`). No per-beam rotation code.

The reviewer confirmed nothing else writes the station's `rotation`: the station's wave entry has
no `.move()` (`level_1_director.gd:239`), so `WaveManager._spawn_ship` attaches no
`EnemyPathMover` (`wave_manager.gd:193-196`) and never sets rotation itself; `ArenaCamera` is
unaffected.

Three visible side-effects, all intended, all to be recorded in `ENEMY.md` in step 5:
the hull spins; the four **turret wrecks** spin with it (`ENEMY.md:54-56` currently records them
as authored at `rotation = 0` with barrels pointing −Y); and the 240×240 core `HurtBox` and contact
`HitBox` spin too, so at 45° their corners reach ~34 px beyond the axis-aligned footprint
(`ENEMY.md:91-102`'s collision table currently reads as if static).

### 6. Teardown

`StationLaserPhase` connects to `BaseEnemy.died` and calls `_stop()`: cancel the volley timer,
clear `_active`, and for each live beam call `dissolve()` if `is_lethal_now()` else `queue_free()`
(`LaserRay.dissolve()` is a no-op outside the IDLE phase, so a beam still warming up needs the
explicit free).

`died` is declared *and* emitted with zero arguments (`base_enemy.gd:4`, `:71`), so this hook does
**not** hit the zero-parameter-signal trap that `Health.amount_changed` does
(`tests/README.md:81-84`).

`BaseEnemy._on_health_changed` emits `died` and then `queue_free()`s the station in the same call
(`base_enemy.gd:65-73`), so the beams would be freed with the subtree at end-of-frame regardless —
but a beam that is lethal *this* frame would still get one kill out of a boss that is already dead.
`_stop()` closes that. It also matters for `LevelSection.ENEMIES_CLEARED`, which polls the enemy
container's child count (`level_director.gd:105-118`): nothing the phase creates may outlive the
station.

### Alternatives rejected

| Alternative | Why not |
|---|---|
| Put the laser logic in `space_station.gd` | Violates the composition convention, and makes the phase impossible to test without the whole boss. |
| A `global/statemachine/` `State` per phase (`ArmoredState` / `LaserState`) | The station has exactly two states and the transition is one-way. `CLAUDE.md` reserves the node-per-file state machine for "complex entities"; simple enemies use in-script phases. A one-way boolean does not earn four new files. Revisit at sub-item 4 if a third phase appears. |
| A second, purpose-built beam scene | `LaserRay` already has telegraph, charge-up, active window, auto-dissolve, the 0.1 s re-hit tick, `is_lethal_now()` and `dissolve()`. Building a second one duplicates all of it and gives the player two beam visuals that mean the same thing (finding 7 argues the opposite: distinct visuals should mean distinct threats). |
| Per-angle emitter standoff so no beam ever overlaps the hull | See §2. Cosmetic gain, more code, contradicts spike 3's measurement that geometry is not a safe primary defence, and disarms test 6. |
| Persistent `Marker2D` emitters authored in the scene | The angle list is what varies per volley; fixed markers would force either RNG or reparenting. Spawning at a computed offset is fewer nodes and directly assertable. |
| Lower `_KILL_DAMAGE` for chip damage instead of one-hit-kill | Research Q3: `_KILL_DAMAGE` is shared with the race hazards and the level's own laser columns, so it is a shared-behaviour change outside this sub-item. Genre norm is that beam damage is *avoidable*, not small; the player's shield already absorbs one hit of any size (`player_base.gd:105-119`). Fairness is bought with the telegraph. |

## Build sequence

Each step is independently runnable and leaves the gate green.

1. **`LaserRay.hit_mask_override`** — add the export + the one-line `_ready()` change, with the
   "set before `add_child()`" note in the doc comment. Add
   `tests/integration/test_laser_ray_hit_mask.gd` (**integration**, not unit — `LaserRay._ready()`
   needs `$BeamSprite`/`$HitZone`, and `tests/README.md:16` forbids scene loading in `unit/`):
   default (0) still yields `128|256|512`; a set override yields exactly that value.
   **Also in this step:** `git rm` the four tracked files under `spike/` (`test_spike_laser.gd`,
   `test_spike_selfkill.gd` and their `.uid`s). They are dead code against the exact scripts this
   item changes; `1-context.md` has been corrected to stop claiming they were already deleted.
   *(Shared-code change, done first and alone so a regression here is unambiguous.)*
2. **`SpaceStation.armor_broken`** — signal, `_armor_broken` guard, turret `destroyed`
   subscriptions. **Test 3, plus an `armor_broken`-only version of test 1's negative case** (kill 3
   of 4, assert the signal has not fired). No laser code yet. *(Revision 2: tests 1 and 2 as
   written assert `is_active()` and count `LaserRay` children — API that does not exist until
   step 4 — so they move there. Review round 2, D3.)*
3. **`SpaceStationConfig`** — five new `@export`s + the values in `space_station_config.tres`.
   Test 10.
4. **`StationLaserPhase`** node + script, added to `space_station.tscn` as `LaserPhase`. Trigger,
   the §3a config copy, rotation, volley timer, beam spawning, `_stop()`. Tests 1, 2 and 4–9.
5. **Docs** — `updating-project-docs`: the station's `ENEMY.md` (including the three rotation
   side-effects from §5), `docs/architecture/modules/assault.md`,
   `docs/architecture/PROJECT.md`, and `docs/enemy-roster.md` if the station is listed there.

## Test plan

New file **`tests/integration/test_station_laser_phase.gd`**, plus `test_laser_ray_hit_mask.gd`
from step 1. Both are integration tests: they instance real scenes, and `tests/README.md:16` says
`unit/` does no scene loading. These assert *intent*, not existing behaviour — like
`test_space_station.gd`, this is new code.

Tests shorten the timings by writing the **phase node's own fields** (§3a) — never `station.config`,
which is a process-wide shared resource — before the phase starts. The shipped values are asserted
separately against the `.tres` in test 10.

**Test timings: `warn 0.2 / active 0.3 / interval 2.5`.** Revision 1 used `interval 1.0`, which
**inverted the invariant test 2 exists to check** (review round 2, D2): at those durations a beam
lives a measured **1904 ms**, so volley 2 would spawn while volley 1's beams were still
dissolving and the phase would hold **4** `LaserRay` children, not 2 — making test 2 either flaky
or simply false, and making test 8's per-volley attribution ambiguous. `interval 2.5` preserves
the shipped `interval > lifetime` relation that the risk table leans on, at a cost of ~1.5 s per
test.

Trimmed from revision 0 on the reviewer's scope note: the standalone `collision_mask == 128`
assertion is folded into test 6 rather than being its own test, and the duplicate listing of
step 1's file is removed. Ten tests, not twelve.

| # | Test | Asserts | Why it can fail |
|---|---|---|---|
| 1 | `test_phase_does_not_start_while_any_turret_lives` | Kill 3 of 4, wait 30 physics frames → `is_active() == false`, zero `LaserRay` children, `station.rotation == 0.0`. | The backlog's first done-condition. An implementation that starts on the *first* `destroyed` fails here. |
| 2 | `test_phase_starts_when_last_turret_dies` | Kill all 4 → `is_active()`, and after the first volley exactly `laser_beam_count` `LaserRay` children exist. | The other half of the done-condition. Also catches beam leakage across volleys. |
| 3 | `test_armor_broken_emits_exactly_once` | **Boundary.** Kill all 4, then call `turret.destroyed.emit(turret)` on already-dead turrets 3 more times → `assert_signal_emit_count(station, "armor_broken", 1)`. | **Rewritten in revision 1.** The original (re-emitting `received_damage`) could not fail: `station_turret.gd:45-47` returns early when `not _alive`, so it never reaches `Health`. Driving `destroyed` directly does re-enter the station's subscription, and does double-fire without the guard. |
| 4 | `test_beam_is_not_lethal_during_the_warning_window` | Add a stub `HurtBox` (layer 128) inside the beam path, step physics to `warn_duration * 0.5` → beam's `is_lethal_now() == false` **and** the stub received **zero** `received_damage` emissions. | The backlog's second done-condition, negative half. Spike 1 proved headless GUT really drives the beam, so this is a genuine physics assertion. |
| 5 | `test_beam_damages_the_player_during_the_active_window` | Same stub, step past `warn + 0.56 s` → `is_lethal_now()` **and** damage count > 0 with value `9999`. | Positive half. Catches a beam that telegraphs and then never arms — which test 4 alone would happily pass. |
| 6 | `test_beam_does_not_damage_the_station_that_fires_it` | **The regression test for spike 2. Repaired in revision 1: it must force a DIAGONAL volley** (set `_volley_index` to 2 before the phase starts) — at `emitter_radius = 140` an axis-aligned beam misses the core hurtbox by 20 px and the test is vacuous. Real physics, no direct emits: all turrets dead (core un-armoured), let the volley go fully lethal for ≥ 0.5 s → `station.health.current_health == max_health`, station still in the tree, **and** the spawned beam's `$HitZone.collision_mask == 128` with bits 256 and 512 clear. | Reverting `hit_mask_override` drops the station 600 → 0 in one frame (reviewer reproduced this). Docstring records that if the emitter ever moves outside the hull on all angles, only the mask assertion still bites. |
| 7 | `test_station_rotates_only_during_the_laser_phase` | Rotation is exactly 0.0 after 30 frames with turrets alive; after the phase starts, `rotation` over `n` physics frames matches `laser_rotation_speed * elapsed` within tolerance. | Catches rotation that starts at spawn, and a speed that ignores the config. |
| 8 | `test_volley_angles_are_deterministic` | Record the local `rotation` of the beams from volleys 0..3 on two freshly-built stations (rotation speed forced to 0 to isolate the angle list) → identical sequences; and within one volley the two beams are `PI` apart, via `assert_almost_eq` / `angle_difference` (`Node2D.rotation` is float32-backed: `PI * 1.25` reads back `3.92699074745178`, not `3.92699081698724`). | Finding 5. Fails the moment someone reaches for `randf()`, which is the natural reading of "varying positions". |
| 9 | `test_beams_stop_and_do_not_outlive_the_station` | With the phase running and a beam lethal, kill the core → `is_active() == false`, no `LaserRay` remains lethal, and after `await get_tree().process_frame` the station is freed. | Guards `ENEMIES_CLEARED` (`level_director.gd:105-118` polls container child count) and the post-mortem kill. |
| 10 | `test_config_laser_values_win_over_script_defaults` | The five new fields on the live station equal the `.tres` values, and the `.tres` values differ from the script defaults for at least one field. | `CLAUDE.md`'s config-driven rule. The "must differ" clause is what stops this test passing vacuously. |
| — | `test_laser_ray_default_hit_mask_is_unchanged` (step 1's file) | A `LaserRay` with `hit_mask_override == 0` has `collision_mask == 128\|256\|512`; with the override set, exactly the override. | Pins the shared-code change so the race hazards and the level's laser columns cannot silently narrow. |

## Risks

| Risk | Check |
|---|---|
| The mask fix regresses the race hazards or the level's laser columns, which need the full `128\|256\|512`. | Step 1's test pins the default. The gate boots the project and runs the existing race-hazard tests. |
| Rotating the station also rotates its 240×240 core `HurtBox` and contact `HitBox`, so the hull corners sweep ~34 px beyond the static footprint. | Intended — the rotating hull *is* part of the threat. Recorded in `ENEMY.md` in step 5. If it reads badly, `laser_rotation_speed` is the single knob. |
| `LaserRay` uses `get_tree().create_timer()`; a beam freed mid-timer could fire a callback on a freed object. | `create_timer` callbacks are dropped when the target is freed, and spike 1 ran a full beam lifecycle in headless GUT without error. Test 9 exercises free-while-warming explicitly. |
| Beams accumulating if a volley fires faster than beams dissolve. | `laser_volley_interval` (6.5) exceeds the measured full beam lifetime (4727 ms), leaving 1.77 s clear. Test 2 asserts the exact child count after a volley, which catches leakage — and the **test** config keeps the same `interval > lifetime` relation (2.5 vs 1904 ms), which revision 1 had broken. |
| A test writes to `station.config` and silently rewrites the shipped `.tres` values for every later test in the process. | §3a: the phase copies the timings into its own fields and nothing reads `config` after `_ready()`; tests override the phase node. Test 10 asserts the `.tres` values and would go red if this regressed. |
| Physics-timing flakiness in tests 4/5 around the phase boundary. | Assert at `warn * 0.5` and at `warn + 0.56 + margin`, not at the boundary itself. The reviewer's measurements (warn 0.0 → 697 ms, 0.5 → 1062 ms, 1.2 → 1766 ms) give the margins. |
| `StationLaserPhase` instanced outside a `SpaceStation`. | Guarded `get_parent() as SpaceStation` null check; the node disables itself. |
| Scope: 5 steps + 10 tests + docs. | The reviewer flagged revision 0's 12 tests as the upper bound of one session; two have been merged away. Steps 1–3 are each small and independently green, so a window that ends early leaves a working tree, not a half-built phase. |

## Out of scope

- **Sub-item 4** — bullet-hell patterns, turret fire, reinforcement waves from the screen edges.
  Finding 7's "simultaneous patterns must look different" is a constraint *on that item*, recorded
  here, not solved here.
- **Sub-item 5** — the death sequence and the handoff into `planet_approach`.
- Any new art. The phase reuses `laser_ray.tscn`'s existing sprite frames; no PixelLab generation,
  so the `pixel-art-generation` skill is not triggered.
- Changing `LaserRay._KILL_DAMAGE`, the beam visuals, or the beam's 0.1 s re-hit tick.
- A dedicated warning colour for the station's beams. Finding 3 notes ULTRAKILL had to patch its
  beam warning colour for readability — worth a look later, but it is an art/shader change and the
  existing `laser_init` telegraph is already the shipped, player-legible one used elsewhere in
  Level 1.
- Per-turret scoring, and any change to the armour rule itself.
