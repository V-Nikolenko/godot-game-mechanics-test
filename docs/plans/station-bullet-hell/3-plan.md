# Station bullet-hell fire (EPIC sub-item 4a)

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

- Owns **one `BulletPool`**, shared by all emitters.
- Phase 1 — a `Timer` at `turret_fire_interval`. Every tick, **every live turret** fires one aimed
  fan. All live turrets fire on the same tick: research finding 2 (chunking) says a legible volley
  beats four independently drifting timers, and it makes "one fewer gun" instantly readable.
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
| `base_angle: float = 0.0` | Base direction in radians. Written by the caller between shots to precess a ring — see the note on runtime state below. |
| `aim_at_player: bool = false` | When true, `base_angle` is added to the angle toward the nearest node in group `player` (falling back to `Vector2.DOWN` when there is no player, exactly as `AimedAttackPattern` does). |
| `bullet_damage: int` / `bullet_speed: float` | Written onto the acquired bullet's `HitBox` and `speed`, same as the shipped patterns. |
| `spawn_radius: float = 0.0` | Each bullet spawns this far from the ship **along its own angle**, so a ring emerges from the hull rim and a fan emerges from the barrel mouth instead of from the entity's centre. |

Turret fan = `count 3, arc 0.35, aim_at_player true, spawn_radius 26`.
Core ring = `count 10, arc TAU, aim_at_player false, spawn_radius 130`, `base_angle` advanced by
the gunnery each shot.

**Runtime state stays in the node, not the resource.** `attack_pattern_resource.gd`'s header is
explicit that patterns are configuration only so that ships can share a `.tres`. The precession
counter therefore lives on `StationGunnery` (`_ring_angle`), which assigns `pattern.base_angle`
immediately before each `fire()`. The gunnery also builds its patterns with `.new()` and never
loads a shared `.tres` — the same thing `interceptor.gd:36` does.

### Where the `BulletPool` node has to live, and why it is not a child of the gunnery

`bullet_pool.gd:40` hardcodes its bullet container as `get_parent().get_parent()`. A pool under the
gunnery would resolve to the **station**, so every in-flight bullet would be a child of the hull —
and `StationLaserPhase._physics_process` rotates the hull, so the whole bullet field would swing
around with it. Same failure for a pool under a turret.

So `StationGunnery._ready()` does `_station.add_child(_pool)`, making the pool a *direct* child of
the station: `pool → SpaceStation → enemy_container`. Bullets then live in `enemy_container` in
world space, exactly like every other enemy's. This is documented at the call site. The considered
alternative — adding a `container_override` export to `BulletPool` — is rejected under
*Alternatives*.

`pool_size = 48`. Derivation: phase 1 peak is 4 turrets × 3 bullets per 1.8 s = 6.7 bullets/s; a
bullet expires at the arena bounds in `enemy_bullet.gd` (x ∈ [-164, 1444], y ∈ [-444, 1164]), and
from the station at world (640, 180) a downward bullet at 240 px/s covers the ~984 px to the bottom
bound in ~4.1 s → ~27 in flight. Phase 2 peak is 10 per 2.0 s at 210 px/s → ~23 in flight. The
phases are mutually exclusive (a live turret means the armour has not broken), so 48 carries either
with headroom rather than their sum.

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
station's core HurtBox mask is `97 | 1024`, which excludes 256. So the `hit_mask_override` dance
phase 2's beams need has no analogue here. The station's own beams are overridden to mask 128, so
they cannot shoot down its own bullets either. Two cheap assertions pin both halves, because the
laser-phase docs make self-damage look like a property of *the station* rather than of `LaserRay`'s
default mask, and the next person will assume it applies here too.

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
| `core_ring_step` | `0.21` rad (≈12°) | **Must not divide the spacing evenly** (finding 4) or successive rings re-tread the same lanes and leave permanent safe lanes: `0.6283 / 0.21 = 2.99…`, and 0.21 rad is not a rational fraction of TAU. Large enough (12°/ring) that the precession is visible on a 2 s cadence, unlike Sparen's 1.5°-per-2-frames demo. |
| `core_bullet_damage` | `10` | Ring bullets are unavoidable-by-position, so they hit softer than the aimed fan. |
| `core_bullet_speed` | `210.0` | 52 % of player speed — the slowest of the three, because phase 2 already has sweeping beams to dodge. |

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

- **Reuse `AttackController` per turret.** It drives one pattern for one ship (`_ship =
  get_parent()`) with a private timer. Using it means a node parenting controllers onto turrets it
  does not own, four independently drifting cadences instead of one legible volley, and no way to
  stop a dead turret firing without freeing someone else's child. The gunnery calls
  `pattern.fire(ship, pool)` — the same public seam `AttackController` calls — from one timer.
- **A `container_override` export on `BulletPool`.** Would let the pool sit under the gunnery. It
  changes a shared component used by five other ships for no benefit that parenting the pool one
  level up does not already give.
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
   `tests/unit/test_radial_attack_pattern.gd` first and watch it fail.
2. **`SpaceStation.turrets()`** public accessor — one method, no behaviour change.
3. **Config exports** — ten fields on `space_station_config.gd` + values in
   `space_station_config.tres`.
4. **`StationGunnery`** — `station_gunnery.gd`, and a `Gunnery` node in `space_station.tscn`.
5. **`tests/integration/test_station_gunnery.gd`** — written against the plan below, watched fail
   between steps where possible.
6. Gate, then docs (`ENEMY.md`, `docs/architecture/modules/global.md` for the new shared resource,
   `PROJECT.md`), `BACKLOG.md` split + tick.

## Test plan

Two files. Every assertion below is one that can actually go red.

### `tests/unit/test_radial_attack_pattern.gd` — pure geometry, no station

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
6. `test_spawn_radius_places_each_bullet_on_its_own_angle` — `spawn_radius 130`: every bullet is
   130 ± 0.5 px from the ship, and each one's offset direction equals its travel direction.
7. `test_damage_and_speed_are_written_onto_the_bullet` — `HitBox.damage` and `speed` match.
8. `test_it_returns_quietly_when_the_pool_is_exhausted` — **boundary.** Pool of 2, ring of 10: 2
   bullets, no crash. (`BulletPool.acquire` `push_warning`s, which GUT does not treat as a failure.)

### `tests/integration/test_station_gunnery.gd`

Station instanced into a container `Node2D` owned by `add_child_autofree`, per the
`ExplosionEffect` trap in `tests/README.md`. Timings are overridden **on the gunnery node**, never
through `config` — the process-wide-resource trap. Volleys are driven by calling the gunnery's fire
methods directly rather than by awaiting timers, so the tests are deterministic and fast; two
tests exercise the timers themselves.

1. `test_nothing_is_fired_before_the_first_volley` — right after `_ready()`, zero bullets in the
   container. Fails if anything fires on spawn.
2. `test_a_volley_fires_one_fan_per_live_turret` — one forced volley → `4 × 3 = 12` bullets.
3. `test_destroying_turrets_removes_their_guns` — **the headline test.** Kill 2 of 4, force a
   volley → exactly 6 bullets, and they originate from the two *surviving* turret positions
   (asserted by proximity to those positions, so a version that fired 6 bullets from the wrong guns
   still fails).
4. `test_a_dead_station_with_no_live_turrets_fires_nothing` — **boundary.** Kill all four, force a
   volley → 0 bullets.
5. `test_turret_bullets_are_aimed_at_the_player` — stub player off-axis; each fan's centre bullet
   points at it and the outer two straddle it by `± arc/2`.
6. `test_turret_barrels_face_the_player_when_firing` — for each live turret, local −Y rotated by
   `global_rotation` equals the direction to the player within 0.01 rad. Closes the *Discovered*
   item; fails today by ~180°.
7. `test_bullets_live_in_the_enemy_container_not_in_the_station` — every fired bullet's parent is
   the station's parent, and the `BulletPool` is a **direct child of the station**. This is the
   regression test for the rotation trap; it fails if the pool is ever moved under the gunnery.
8. `test_station_bullets_cannot_hit_the_station` — a fired bullet's `HitBox` is layer 256 with mask
   128, and the station's core HurtBox mask has neither bit 256 nor bit 8 (`256 & mask == 0`), so
   the sets are disjoint in both directions.
9. `test_the_core_does_not_fire_until_the_armor_breaks` — before: `is_core_firing()` false and a
   forced ring produces nothing. After killing all four turrets: `is_core_firing()` true.
10. `test_a_core_ring_is_a_full_evenly_spaced_ring` — 10 bullets, gaps `TAU/10`, all `130 ± 0.5` px
    from the station centre.
11. `test_successive_rings_precess_by_the_configured_step` — two forced rings; ring 2's angles are
    ring 1's plus `core_ring_step`, mod `TAU`.
12. `test_the_ring_step_does_not_divide_the_ring_spacing` — a **design lock** on the shipped
    values, the direct analogue of `test_volley_angles_are_deterministic`: asserts
    `fmod(TAU / core_ring_count, core_ring_step)` is not within 0.001 of 0 or of the step. Fails
    the moment someone "tidies" the step to 30°/4 and reintroduces permanent safe lanes.
13. `test_turret_fire_stops_when_the_armor_breaks` — the turret timer is stopped after
    `armor_broken`.
14. `test_everything_stops_and_bullets_are_freed_when_the_station_dies` — fire a volley, kill the
    core, wait one frame: both timers stopped, and no `EnemyBullet` remains in the container. This
    is what stops dead-boss bullets holding `ENEMIES_CLEARED` open.
15. `test_volleys_are_deterministic` — two forced volleys with the player unmoved produce identical
    direction sets. Fails the moment anyone reaches for `randf()`.
16. `test_config_values_are_copied_onto_the_gunnery` — the node's fields equal the shipped `.tres`
    values. Not vacuous: the node's own defaults are deliberately different (a conservative
    single-bullet, slow, low-damage fallback), and the test also asserts `config` itself is
    unchanged afterwards.
17. `test_the_timers_actually_run` — one timing test, not sixteen: set `turret_fire_interval` to
    0.2 on the node, `await` ~0.5 s, assert at least one volley landed. Everything else is forced.

### Watch-it-fail plan

Steps 1 and 4 land their tests before their implementation. For test 6 the red is already
available today (barrels are at `rotation = 0`, pointing 180° away). For test 7, temporarily
parenting the pool under the gunnery must turn it red before the final commit — that check is the
only thing standing between this design and a silently rotating bullet field.

## Risks

| Risk | Check |
|---|---|
| Pool exhaustion at 48 under some pattern (fires `push_warning`, bullets silently missing) | Unit test 8 pins the graceful path; the derivation above is in the code comment so the next tuner recomputes it |
| Phase 2 too dense: 10 bullets/2 s **plus** two sweeping beams on a stage-1 mini-boss | Numbers are all `.tres` knobs; `core_ring_interval` is the single dial, documented in `ENEMY.md`. Genuinely unverifiable headless — flagged as needing a play test |
| Phase 2 has **no aimed component**, so research finding 1 says a safe spot is possible | Mitigated by three moving layers (hull rotates, ring precesses, beams sweep); recorded in `ENEMY.md` as the thing to re-check if the phase reads as safe-spottable |
| `_ready()` ordering: reading `_station.turret_root` before the station readies | Designed out — turrets are resolved lazily per volley. Test 2 would fail immediately if this regressed |
| Bullets holding `ENEMIES_CLEARED` open after the boss dies | Test 14 |
| Config mutation leaking across the suite | Overrides applied to the node only; test 16 asserts `config` is unchanged |

## Out of scope

- **Reinforcement waves from three screen edges** — sub-item 4b, split out in `BACKLOG.md`.
- Turret scoring, the opaque `station_core.png` background, the `Gunship` `collision_damage` bug,
  and the `base_enemy` hitbox-scale bug — all open *Discovered* items, none touched here.
- Any new art. Bullets reuse `enemy_bullet.tscn`'s existing `Line2D` visual.
- Sub-item 5's death sequence and handoff.
