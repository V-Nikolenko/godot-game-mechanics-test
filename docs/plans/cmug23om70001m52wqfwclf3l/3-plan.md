# Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields — plan (revision 2)

Epic `cmug23om70001m52wqfwclf3l`, plan task `cmug23oml0009m52wqy133sf2`, 2026-10-20. Built on `1-context.md` (code
inventory, requirements R6.1–R6.19) and `2-research.md` (scope check S1–S14, findings F1–F12, starting values) in this
directory, and on the idea's `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (Phases 1–5, as built). Task keys
`t1`–`t19` are the keys in `tasks.json`. Revision 2 answers the round-1 review (`4-review.md`, B1–B4 and M1–M12); §8
lists each point and what changed.

## Summary for the owner

- **For the player:** space gets terrain that matters. A gravity well drags everything in reach, you and enemies alike: small drones that blunder into its core cannot climb out and are crushed; fighters and heavy ships crawl out slowly; in Open Space you must boost out of the core. An energy anomaly pulses on a visible rhythm and, while lit, swirls ships and rockets sideways. Destroyed ships sometimes leave wrecks: hard cover that stops shots from both sides and blocks a sniper's line. Bombers' gravity bombs leave a short slowing field, and a Ram Corvette's broken armour plates fly off as dangerous fragments.
- **Enemies read the battlefield:** every new-style enemy steers round hazards with its own temperament (drones skim the edge, heavy ships are cautious and resist the pull), but any ship in a committed attack run ignores hazards and can be baited into a well. The Sniper shoots from beside a wreck, a lone Fighter (or a squad's leader) waits behind one before its pass, and a Ram near a well circles to the far side of you so its charge shoves you into the well.
- **Where you meet it:** the Open Space hub gains one tactical space away from the planets (a well, an anomaly, three derelict structures). Patrols chase you there if you lead them. Level 1 gets only what its enemies leave: wrecks, slow fields, fragments.
- **Built:** a shared hazard description and registry, pull and slow for enemies and both player ships, a context-steering avoidance stage in the enemy mover, the well, the anomaly, wrecks (inert, explosive, placed, fragments), the Gravity Field, the three cover and well tactics, top-down art.
- **Left out:** mines (phase 7), laser walls (8), jammers and EMP zones (9), capital-ship and boss wrecks (19), hazards for legacy and rail-driven enemies (10, 15), cover for squad wingmen (14).
- **Risks:** the avoidance stage sits on every enemy's movement; tests pin that it changes nothing when no hazard is near. The test suite will end near 236 s of its 240 s ceiling, so the next phase must recover time first. Wrecks in live level 1 could slow the last enemies' exit; one replay row guards it. Nothing has been play-tested; every number is a starting value.
- **Choices I made for you (tell me if you want otherwise):**
  1. Which projectiles bend in a well? *Default: rockets, bombs and your missiles; bullets fly true.*
  2. What does the anomaly distort? *Default: a pulsed sideways swirl on ships and rockets, not shields or targeting.*
  3. Debris Charge passive or active? *Default: broken ram plates fly off; no deliberate plate throw.*
  4. Does an exploding wreck hurt enemies too? *Default: yes, it is the environment, not an enemy weapon.*
  5. Wrecks in Assault? *Default: yes, at most 4 at once, drifting off the bottom.*
  6. Place a well or anomaly in level 1? *Default: no; that waits for the Assault level rework (phase 15).*
  7. Which fighters take cover? *Default: lone fighters and a squad's leader; wingmen keep their formation.*

## For every task

**Scope.** Phase 6 of 20. Build only what your sections name; mines (Ph7), laser walls (Ph8), jammers / EMP (Ph9),
heavy-ship and boss wrecks (Ph19) are later. Hazards affect **mover-driven** enemies only (the nine brains: swarm,
razor, fighter, gatling, bomber, sniper, ram, missile corvette, support); rails and legacy enemies are untouched.
**Names (new, shared — do not rename).** `global/hazards/`: `HazardInfo` (`hazard_info.gd`, `RefCounted`), `Hazards`
(`hazards.gd`, static registry), `HazardField` (`hazard_field.gd`, the one field script), `HazardDrift`
(`hazard_drift.gd`). `assault/scenes/hazards/`: `gravity_well/`, `energy_anomaly/`, `gravity_field/`,
`reactor_field/`, `wreck/` (`Wreck`, `DebrisFragment`, `WreckScenes`). Groups: `hazard_container`, `wrecks`.
`HazardInfo.kind`: `&"gravity_well"`, `&"anomaly"`, `&"gravity_field"`, `&"reactor_field"`, `&"wreck"`, `&"debris"`.
**Model: hazards are sampled by the body.** A hazard node answers duck-typed `hazard_info() -> HazardInfo`, calls
`Hazards.register(self)` in `_enter_tree()` and `Hazards.unregister(self)` in `_exit_tree()`. Queries:
`Hazards.accel_at(pos)` (pull + swirl, px/s²), `Hazards.penalty_at(pos)` (strongest slow only, capped at
`Hazards.MAX_PENALTY` 0.5), `Hazards.around(pos, reach)`, `Hazards.count()` (O(1)). **A hazard never writes a ship's
velocity, position or rotation**; no `Area2D` fields, so **collision bit 12 stays unallocated**. Direct damage from a
hazard is `Hazards.pulse_damage(tree, at, radius, damage)`: a `HurtBox.received_damage.emit(n)` on every node of groups
`enemies` and `player` whose **centre** is within `radius` (hull stress, explosive-wreck blast; bypasses `EnemyShield`).
**Claims** live on `HazardInfo`: `try_claim(node) -> bool`, `release(node)`, `is_claimed_by(node)`, stored as an
instance id so a freed claimer frees the claim. One user per wreck (cover) or per well (the Ram's ticket).
**Enemies.** `EnemyMover` stays the single writer (`test_enemy_mover_single_writer.gd`). Step: desired (boost or capped
request) → × slow factor → context avoidance (skipped while boosting) → accel limit on `own_velocity()` → `+ drift`
only if non-zero (applies while boosting) → corridor `constraint.filter()` last → write. `EnemyMover.own_velocity()` =
`actor.velocity − last drift` (exactly `actor.velocity` when the drift is zero); brain "am I settled / stopped" gates
read it, never raw `actor.velocity`. **Pass-through rule:** with no hazard in reach and zero drift, velocity and
rotation are bit-identical to today; `Hazards.count() == 0` costs one compare. Profile: three flat `ShipConfig` fields
(`@export_group("Hazards")`) `hazard_avoidance` 0..1, `hazard_margin` px, `hazard_resistance` 0..1, copied onto the
mover by `BaseEnemy._ready()`. Committed attacks are `mover.boost()` and so ignore avoidance — never add a separate
"ignore hazards" API. The avoidance stage skips only a line-of-sight-blocking hazard **claimed by its own actor** (the
ship's cover).
**Players.** The Open Space ship adds `accel · dt` to its own `velocity`; the Assault fighter is displaced by a
`HazardDrift` in its own `_physics_process` and clamped there. `ShipTurnController` stays the only writer of the Open
Space ship's rotation; a pull never rotates a ship.
**Runtime spawns** (wrecks, fragments, Gravity Fields, reactor fields) go into `Hazards.container(tree)` (first node in
group `hazard_container`). **No container → spawn nothing and draw no rng.** Spawns happen inside physics callbacks
(a bullet's `area_entered` kills a ship or breaks a plate), so **every spawn is deferred**: the spawner captures position,
rotation and velocity at once and calls the new node's `spawn_into(container, at, rot)`, which stores them and calls
`_attach.call_deferred(container)` on itself (the `ContactBlast.spawn` / `_attach` pattern: frees itself if the container
is gone; applies the transform in `_enter_tree()`). Never into the enemy container (it holds `ENEMIES_CLEARED` open,
`level_director.gd:170`), never into group `enemies`, never scored. Each spawned hazard frees itself (one owner).
**Determinism.** Randomness only from the dying enemy's `brain.rng` (seeded); no `Timer` nodes; clocks are accumulated
`delta` in `_physics_process(delta)`. Tests hand-tick `HazardField._physics_process(d)` and drive enemies with
`test_enemy_dual_mode.gd`'s `_tick()`. Collision rows (a body hits a wreck, a shot hits a wreck, a LOS ray, a kill by a
real bullet) use real physics on the 8× clock (`_scale_clock()` / `_restore_clock()` in `test_level1_drone_exit.gd`).
**Tests.** Failing test first. "Dual-mode" means `func test_x(mode: String = use_parameters(["open_space",
"assault"]))`, harness built in the body from `tests/helpers/enemy_ai_harness.gd`. Add hazard nodes with
`add_child_autofree` so the static registry is empty after each test. Read `tests/README.md` first; run
`scripts/check-test-leaks.sh` after anything that awaits. GUT fails a test on any unexpected engine error, which is
what makes the real-physics spawn rows meaningful.
**Gate time.** GUT must stay ≤ 240 s (≈ 200 s at the end of Ph5). Run `scripts/gate-time.sh` before and after, report
both, stay within your section's **allowance**. If GUT is above 232 s before you start, recover time first by the
README's three rules and say so.
**Coordinates / art / docs.** Assault waves stay in 640×360 design units; nothing in `global/` references `ArenaCamera`
(use `EnemyWorld`). Hazard radii and speeds are world px. Art: invoke `pixel-art-generation` first, strict top-down
(`view: "high top-down"`, `isometric: false`), save with `./scripts/pixellab.sh`, look at every image, transparent
background. Never hand-type a `uid://`. Each new hazard gets a `HAZARD.md`; a deviation later phases depend on goes into
the Phase 6 section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`. Gate: `bash /agent/verify.sh`.

## 1. Problem

Today the battlefield is empty: Open Space has no terrain at all, Assault has only asteroids, and no enemy reacts to
anything but the player. Enemies cannot be lured into danger, cannot take cover, and nothing in the world shapes a
fight. Phase 4 built a line-of-sight rule that nothing in shipped content ever blocks.

After this phase: hazards are part of one shared simulation. A gravity well pulls the player and every AI enemy by the
same field, scaled by each ship's resistance; enemies see the same hazards and steer round them according to their
profile, except in a committed run, where they can be baited in. Destroyed ships sometimes leave wrecks that block shots
and sight lines, and three enemies use hazards as tools: the Sniper fires from beside a wreck, the Fighter waits behind
one before its pass, and the Ram circles to the far side of the player from a well so its charge drives the player in.

### 1.1 Scope adjustments from the research (S1–S14 in `2-research.md` §0)

| Id | Adjustment | Why |
|---|---|---|
| S1 | Context steering as a **stage inside `EnemyMover`**, not in nine brains; no repulsion nudges | Keeps Ph1's rejection of weighted blending and implements its named Ph6 upgrade without rewriting tested brains |
| S2 | New `HazardInfo` + static `Hazards` registry; the same objects drive physics and AI perception | Nothing exists; the race `HazardSystem` is the precedent ("what the AI dodges is what kills it") |
| S3 | **Bit 12 `area_control` not allocated** | A sampled field needs no physics layer; Ph1's rule "no layer until something uses it" |
| S4 | §11.4 Gravity Field moved here from Ph7 | This board's scope; Ph7 keeps mines |
| S5 | Debris Charge on the Ram Corvette's plates | The only breakable armour that exists |
| S6 | LOS needs no change; add `EnemyBrain.can_see_player()` and the first shipped blockers | Ph4 built `LineOfSight` with the `blocks_line_of_sight()` hand-over |
| S7 | Satellite / cargo platform / station module = art variants of a placed `Wreck` | Only wrecks and debris behave differently |
| S8 | Unstable reactor field = a damage-only `HazardField` left by an explosive wreck; EMP zones → Ph9; `disables_abilities` ships as a field with no producer | The jammer is EMP's natural consumer |
| S9 | Capital-ship wrecks and "modules remain as wreckage" → Ph19 | No capital ships yet |
| S10 | Carrier / hacker tactics out | Ph10/18 and Ph9 |
| S11 | Mover-driven enemies only | Rails own position until Ph15; Gunship Ph10; station immovable |
| S12 | Projectiles opt in per family (rockets, bombs, player missiles) | Bullet and round lifetime gates assume straight lines |
| S13 | Hub: one tactical space; level 1: only what its enemies bring | Level-1 gates are calibrated without hazards |
| S14 | O(1) early-out when no hazard exists | `test_fighter_squad.gd` ticks movers ~186k times |
| S15 (rev 2) | Fighter cover for solo fighters and a squad's LEAD only; wingmen (FLANK / REAR) keep their S hold | A wingman's S moves with the player and is governed by the squad window; cover for wingmen belongs with Ph14's squad communication |

## 2. Design

### 2.1 HazardInfo, the Hazards registry, HazardField and HazardDrift (t1)

All four live in `global/hazards/`. Pure maths is static or on `HazardInfo`, so it is unit-testable without a scene.

**`HazardInfo`** (`RefCounted`). Each hazard node owns **one** instance, updates it in place (position every physics
frame for moving hazards, state on phase changes) and returns it from `hazard_info()`. Callers treat its fields as
read-only; the claim methods are the one mutable part.

| Field | Type | Meaning |
|---|---|---|
| `position` | Vector2 | centre, world px |
| `radius` | float | outer edge of every effect: pull reach, slow area, avoidance footprint |
| `pull_force` | float | radial acceleration at the core, px/s², toward the centre (0 = none) |
| `damage_per_second` | float | hull stress inside `damage_radius` (= `stress_damage / stress_period`; for the AI) |
| `movement_penalty` | float | 0..1 slow inside `radius` |
| `disables_abilities` | bool | carried for Ph9; no producer or consumer this phase |
| `line_of_sight_blocker` | bool | mirrors the body's `blocks_line_of_sight()` |
| `kind` | StringName | `&"gravity_well"`, `&"anomaly"`, `&"gravity_field"`, `&"reactor_field"`, `&"wreck"`, `&"debris"` |
| `core_radius` | float | softening radius: the pull is constant inside it |
| `damage_radius` | float | hull-stress radius |
| `tangential_force` | float | swirl acceleration at the core, px/s²; **its sign is the direction** (+ = clockwise in screen space); an instance flips the swirl by setting a negative value — there is no separate `clockwise` export |
| `avoid_weight` | float | 0..1, how bad entering is (well 1.0, reactor 1.0, anomaly 0.7 while lit / 0 quiet, gravity field 0.6, wreck 0.6, debris 0.4) |
| `velocity` | Vector2 | drifting hazards; avoidance leads them |
| `source` | Node | the hazard node |
| `claimer_id` | int | instance id of the claimer, 0 = free |

Methods: `falloff(r) -> float` (profile below, 0..1), `accel_at(pos) -> Vector2` (radial `pull_force` + tangential
`tangential_force`, both × falloff), `penalty_at(pos) -> float` (`movement_penalty` inside `radius`, else 0),
`contains(pos, margin := 0.0) -> bool`. **Claims:** `try_claim(node) -> bool` (succeeds when free, when the claimer is
`node` already, or when `instance_from_id(claimer_id)` is null — a freed claimer), `release(node)` (only the claimer can
release), `is_claimed_by(node) -> bool`, `is_claimed() -> bool`. Used by the Sniper and Fighter (one ship per wreck) and
the Ram (one Ram per well).

**Field profile** (softened 1/r, short reach, no hard edge — F4–F7): `falloff(r) = 1` for `r ≤ core_radius`;
`core_radius / r` out to `0.85 · radius`; then a linear taper to 0 at `radius`; 0 beyond. Finite at `r = 0`; the
direction at `r = 0` is `Vector2.ZERO` (no NaN).

**`Hazards`** (static class, `static var` storage):
- `register(node)`, `unregister(node)`, `count() -> int`, `MAX_PENALTY := 0.5`.
- `around(pos, reach) -> Array` — infos with `pos.distance_to(info.position) ≤ info.radius + reach`. Allocates; call only
  when `count() > 0`.
- `accel_at(pos) -> Vector2` — sum over all infos. `penalty_at(pos) -> float` — `min(MAX_PENALTY, max over infos)`
  (strongest only, never stacked — F12).
- `container(tree) -> Node2D` — first node in group `hazard_container`, or null.
- `hurt_box_of(ship) -> HurtBox` — `ship.get("hurt_box")` if it is a `HurtBox`, else the child named `HurtBox`, else
  null. Both player ships have a child `HurtBox` whose `received_damage` is scene-connected to their damage handler
  (`player_ship.gd:530`, `player_fighter.gd:172`); verify the node name when implementing.
- `pulse_damage(tree, at: Vector2, radius: float, damage: int) -> int` — for every node in groups `enemies` and
  `player` whose `global_position` is within `radius` of `at` (centre distance, `≤`), emits `damage` on
  `hurt_box_of(node).received_damage`; returns how many were hit. A direct emit: it bypasses `EnemyShield` (which hooks
  `area_entered`), the player's own damage path treats it like any hit, and a plated Ram deflects it (its
  `_on_received_damage` deflects every hit while a plate lives). Used by hull stress (§2.1) and the explosive-wreck blast
  (§2.10). Safe inside a physics callback (it adds no body).

**`HazardDrift`** (`RefCounted`): `velocity: Vector2`, `half_life := 0.35`,
`step(accel: Vector2, resistance: float, delta: float) -> Vector2`:
`velocity += accel · (1 − resistance) · delta; velocity *= pow(0.5, delta / half_life)`; snap to `Vector2.ZERO` below
0.5 px/s; returns `velocity`. `reset()`. Terminal drift in a constant field is `a · (1 − res) / k`, `k = ln 2 / 0.35 =
1.98 /s`.

**`HazardField`** (`Node2D`, `class_name HazardField`) — the one script behind the well, the anomaly, the Gravity Field
and the reactor field (composition: a scene sets exports and adds its sprite). Exports: `kind`, `radius`,
`core_radius`, `pull_force`, `tangential_force` (signed), `movement_penalty`, `avoid_weight`, `damage_radius`,
`stress_damage` (int per pulse), `stress_period` (s), `duration` (s, 0 = permanent; frees itself at the end), and the
pulse cycle `cycle_telegraph`, `cycle_active`, `cycle_quiet` (all 0 = always active). Signals:
`phase_changed(phase: int)` (enum `Phase { ACTIVE, TELEGRAPH, QUIET }`), `stressed(count: int)`.
`_physics_process(delta)` advances the cycle and duration clocks, writes the live `HazardInfo` (QUIET: `pull_force`,
`tangential_force`, `movement_penalty`, `avoid_weight` all 0; TELEGRAPH: forces 0, `avoid_weight` kept) and, every
`stress_period` while ACTIVE, calls `Hazards.pulse_damage(get_tree(), global_position, damage_radius, stress_damage)`
and emits `stressed` when it hit anyone. `phase_progress() -> float` for art. `hazard_info()`, `try_claim(node)` /
`release(node)` delegate to its info.

**Deferred spawning** (`spawn_into`). `HazardField.spawn_into(container: Node, at: Vector2, rot := 0.0) -> void` stores
`at` / `rot`, sets a `_pending_transform` flag and calls `_attach.call_deferred(container)` **on itself**. `_attach`
(untyped parameter, as `ContactBlast._attach`) adds it to the container if the container is valid and in the tree,
else `queue_free()`. `_enter_tree()` applies the stored transform when the flag is set (a parentless `Node2D`'s
`global_position` is only its local position). `Wreck` and `DebrisFragment` (t10) carry the same three members. This is
the only way runtime hazards are added (a kill or a plate break happens inside an `area_entered` flush, where adding a
physics body synchronously is refused: `global/components/contact_blast.gd:27-33`, `big_asteroid.gd:63`).

**Tests** — `tests/unit/test_hazards.gd`, `tests/unit/test_hazard_field.gd`:
register on enter / unregister on exit; **`count()` is 0 after the node is freed**; `around()` includes a hazard at
exactly `radius + reach` and excludes one 1 px beyond; `falloff`: 1 at the core, `core/r` at 2 × core, **0 at `radius`**,
**finite with zero direction at r = 0**, monotone across the taper; `accel_at` sums two wells; tangential is
perpendicular to radial and a negative `tangential_force` flips it; `penalty_at` **strongest only (0.4 and 0.3 → 0.4)
and capped (0.8 → 0.5)**; `HazardDrift` approaches `a(1−res)/k` within 2 % after 3 s at 60 Hz, halves with resistance
0.5, snaps to zero; claims: a second node is refused, the claimer re-claims, release by a non-claimer is ignored, **a
freed claimer frees the claim**; `pulse_damage` hits a fixture enemy at exactly `radius` and **not at `radius + 1`**,
never a node outside both groups; `HazardField` cycle order TELEGRAPH → ACTIVE → QUIET with the configured lengths,
forces 0 outside ACTIVE, `avoid_weight` kept during TELEGRAPH; stress pulses once per `stress_period`; `duration` frees
the node; `spawn_into` attaches on the next idle frame at the stored transform, and **frees itself when the container
was freed first**; a duck-typed fixture hazard (not a `HazardField`) joins `around()` with no other change (R6.2).
**Allowance: +0.5 s.**

### 2.2 Enemies feel the pull and the slow: EnemyMover drift, speed factor and own_velocity (t2)

`global/enemy_ai/enemy_mover.gd` gains three exports, `hazard_avoidance := 0.0`, `hazard_margin := 0.0`,
`hazard_resistance := 0.0` (an unconfigured mover feels full physics and avoids nothing), a private `HazardDrift`, and
`_last_drift: Vector2`. `ShipConfig` gains `@export_group("Hazards")` with `hazard_avoidance = 1.0`,
`hazard_margin = 60.0`, `hazard_resistance = 0.0`; `BaseEnemy._ready()` copies them onto `_mover` when both exist (a
field write, legal for the single-writer gate; subclasses copy their own config after `super._ready()` and never touch
these three). Per-enemy `.tres` values (starting values, research §3.2):

| Enemy | `hazard_avoidance` | `hazard_margin` | `hazard_resistance` |
|---|---|---|---|
| Swarm Drone | 1.0 | 12 | 0.0 |
| Razor Drone | 1.0 | 16 | 0.0 |
| Fighter | 0.8 | 60 | 0.1 |
| Gatling Interceptor | 0.8 | 60 | 0.15 |
| Sniper | 1.0 | 90 | 0.1 |
| Support Ship | 1.0 | 80 | 0.1 |
| Bomber | 0.6 | 70 | 0.4 |
| Missile Corvette | 0.7 | 80 | 0.4 |
| Ram Corvette | 0.5 | 60 | 0.5 |

**Step order** (the comment block at the top of `enemy_mover.gd` is rewritten to match):
1. desired = boost velocity while boosting, else `(primary + nudge).limit_length(max_speed)` (as today);
2. **slow**: `f = 1 − Hazards.penalty_at(pos) · (1 − hazard_resistance)`; if `f < 1`, desired `*= f` (boost too —
   "movement/boost effectiveness"). `max_speed` itself is never written (brains rewrite it per state);
3. context avoidance stage (§2.4, t4; t2 leaves a no-op hook);
4. accel / braking limit with `current = own_velocity()` (skipped while boosting);
5. **drift**: `d = _drift.step(Hazards.accel_at(pos), hazard_resistance, delta)`; **only if `d != Vector2.ZERO`**,
   `v = v + d` (adding a zero vector turns a `-0.0` component into `+0.0` and flips `angle()` by 2π, so the add is
   skipped). Applies **while boosting** too (physics, R6.3);
6. `constraint.filter(pos, v)` **last**, so a well near the Assault edge never drags an enemy past the hard band;
7. write `velocity`, `move_and_slide()`; `_last_drift = d`;
8. facing: from `v − d` when `d` is non-zero (the ship's own heading), else from `v` exactly as today; or the face point.

`own_velocity() -> Vector2`: `actor.velocity` when `_last_drift == Vector2.ZERO` (the same object value, no
arithmetic), else `actor.velocity − _last_drift`. The private `_vel()` (used by `arrive`, `hold_position`,
`formation_slot`) returns `own_velocity()`. `halt()` (used by `suspend_ai()`) also resets the drift and `_last_drift`.
**Early-out:** when `Hazards.count() == 0` and the drift is zero, skip steps 2, 3 and 5 entirely (one compare). Rails
and legacy enemies have no mover step, so a well never moves them.

**Brain gates switch to `own_velocity()`** (otherwise a ship inside a field never reads as stopped and every such gate
falls through to its cap). Mechanical one-line replacements of `actor.velocity` by `mover.own_velocity()`:
`ram_corvette_brain.gd` LINE_UP `crawl_speed` check (`:395`); `sniper_brain.gd` SETTLE `settle_epsilon` (`:477`);
`fighter_brain.gd` `is_settled()` and `is_braking_onto_station()` (`:382`, `:390`) and the RUN_IN standing-start test
(`_steer_run_in`); `razor_drone_brain.gd` feint stop (`:448`). Other `actor.velocity` reads (headings, leads) stay: a
drifting ship really is moving that way. With no drift every replacement returns the identical value.

Capture table (well of §2.5: `pull_force` 520, `core_radius` 90, `radius` 420; terminal drift `a(1−res)/1.98`):
Swarm 263 px/s drift vs 220 own speed → **captured**, settling near 107 px from the centre (inside `damage_radius`
150, outside `core_radius` 90); Razor captured at approach speed, escapes by dashing; Fighter 236 vs 300 → escapes;
Gatling 223 vs 260; Support 236 vs 270; Missile Corvette 158 vs 210; Ram 131 vs 280.

**Tests** — extend `tests/unit/test_enemy_mover.gd`; add dual-mode rows to `tests/integration/test_enemy_dual_mode.gd`:
**bit-identical velocity and rotation with no hazard** for four movers (instant, accel-limited, boosting, Assault
constrained) over 120 ticks, compared against a recorded run with the registry empty, **including a mover requesting
`-Vector2(200, 0)` (the −0.0 case)**; **the same with a fixture well registered 2000 px away** (drift stays exactly
zero, so the add is skipped); a fixture well (`HazardField`, `pull_force` 520) drags an idle mover inward (dual-mode);
resistance 0.5 drifts about half as far over 1 s; **a Swarm Drone config in the core cannot leave while a Fighter
config can** (seek outward for 3 s); drift persists through a `boost()`; `halt()` zeroes it; `own_velocity()` equals
`actor.velocity` with no drift and excludes the drift inside a well; **a real Ram's LINE_UP inside a well's pull ends
on the line-up test, not at `line_up_cap`** (dual-mode); Assault: a well beyond the corridor's hard band never pulls an
enemy past it; a fixture Gravity Field (penalty 0.4) scales a resistance-0 mover's top speed to 0.6× and a
resistance-0.5 mover's to 0.8×, boost included (dual-mode); an enemy on a rail (`EnemyPathMover`) is not moved by a
well. `test_config_instance_isolation.gd` stays green (flat fields). **Allowance: +1.5 s** (includes the early-out's
cost on `test_fighter_squad.gd`; report that file's time).

### 2.3 Players feel the pull and the slow (t3)

**Open Space ship** (`open_space/scenes/entities/player/player_ship.gd`). A new method `_step_hazards(delta: float) ->
void`, called inside `_handle_thrust()` after the thrust / damping block and before `_step_boost()` (whose ceiling clamp
therefore bounds a pull), adds `Hazards.accel_at(global_position) · delta` to `velocity` when `Hazards.count() > 0`.
Skipped while `engine_boost_active` (the module owns velocity; `_handle_thrust` already returns early). Slow:
`hazard_speed_factor() -> float = 1 − Hazards.penalty_at(global_position)` scales `thrust_acceleration`,
`reverse_acceleration`, the speed ceiling and `boost_exit_speed` where they are read (never written). Rotation
untouched. Consequence: thrust (380 px/s²) cannot out-pull the well where `a > 380`, i.e. inside **123 px** of its
centre — there the player must boost (700 px/s).

**Assault fighter** (`assault/scenes/player/player_fighter.gd`). Its states run from the state machine's `_process`
(`global/statemachine/state_machine.gd:15-17`), not after `_physics_process`, and `idle_state.gd` never clamps — so the
drift is applied **and clamped inside `player_fighter._physics_process` itself**:
- order in `_physics_process`: the `DialogPlayer.is_active` return (also `_drift.reset()` there) → the knockback return
  (no drift during a wall-hit shove: the shove owns movement) → module ticks → the `engine_boost_active` branch (no
  drift during an engine boost: the boost escapes a well, as in Open Space) → **drift step**: `d =
  _drift.step(Hazards.accel_at(global_position), 0.0, delta)` (skipped entirely when `Hazards.count() == 0` and the
  drift is zero); if `d != Vector2.ZERO`, `move_and_collide(d · delta)` then the same clamp as the boost branch
  (x [-100, 1380], y [-380, 1100]) → the thruster block as today;
- `dash_state.gd`'s `move_and_slide()` gains the same clamp (it has none today).
`PlayerBase` gains `hazard_speed_factor() -> float` implemented once as `1 − Hazards.penalty_at(global_position)`
(1.0 when `count() == 0`); the Open Space ship uses it for the reads above, and `move_state.gd` / `dash_state.gd`
multiply `move_speed` / `dash_speed` by it.

**Tests** — new `tests/integration/test_player_hazards.gd`: Open Space ship with no input beside a fixture well drifts
inward; **at 140 px with thrust held outward it escapes; at 100 px it does not; with boost it escapes from 100 px**;
rotation unchanged by the pull; Gravity Field (penalty 0.4) scales thrust and boost exit speed to 0.6×; Assault fighter
**idle** (no state movement) beside a well drifts toward it, calling `_physics_process` only; **with the well beyond the
edge it stops at the clamp** (x ≤ 1380); no drift while `DialogPlayer.is_active` or during knockback; its move and dash
speeds scale by 0.6 in a field; with no hazard every existing `test_open_space_*` / player row is unchanged.
**Allowance: +1 s.**

### 2.4 Soft avoidance: the context-steering stage (t4)

A pure function `Steering.context_avoid(pos, desired, infos, avoidance, margin, lookahead, prev_dir) -> Vector2` in
`global/enemy_ai/steering.gd`, called by `EnemyMover.step()` at step 3 (after the slow, before the accel limit) when
**not boosting**, `hazard_avoidance > 0`, `desired` is non-zero and `Hazards.count() > 0`. The mover collects infos from
`Hazards.around(pos, hazard_margin + |desired| · lookahead)` and **drops any info with `line_of_sight_blocker` that
`is_claimed_by(actor)`** — the wreck the ship has claimed as cover is its destination, not a danger (the body itself
still collides). Wells are never skipped, claimed or not (the Ram must still avoid its well while setting up). No infos
left → return `desired` unchanged (pass-through).

Algorithm (Fray's context steering, F1/F2; constants on `Steering`: `CONTEXT_SLOTS := 16`, `CONTEXT_LOOKAHEAD := 0.6`,
`CONTEXT_PREV_BLEND := 0.5`, `CONTEXT_MIN_SPEED_RATIO := 0.35`):
1. **Interest** per slot `u_i`: `max(0, cos(angle(u_i, desired)))`.
2. **Danger** per hazard, merged per slot by **max** (never summed): with `d` = distance to the hazard's centre (led by
   `info.velocity · lookahead`), `R = info.radius`, `M = margin + |desired| · lookahead`:
   - outside (`d > R`): `skirt = clamp(1 − (d − R) / M, 0, 1)`; angular half-width `θ = asin(min(1, (R + margin) / d))`
     widened by one slot; slot danger = `avoid_weight · skirt · clamp(1 − angle(u_i, toward) / θ, 0, 1)`;
   - inside (`d ≤ R`): slot danger = `avoid_weight · max(0, cos(angle(u_i, toward)))` — outward slots get 0, so a ship
     inside always steers out.
3. **Profile threshold** (R6.8): a slot's danger counts only above `1 − hazard_avoidance` (subtracted, floored at 0).
   Fray's masking is scale-invariant, so scaling danger would do nothing; the threshold makes a 0.5-avoidance ship
   ignore glancing danger and react only when heading squarely in.
4. If every slot's danger is 0 → return `desired` unchanged.
5. Mask every slot with more danger than the minimum; among the rest pick the highest interest; refine the heading by
   parabolic interpolation with the two neighbours (no 22.5° quantisation); blend with `prev_dir` by
   `CONTEXT_PREV_BLEND` (hysteresis; the mover keeps `prev_dir`, cleared when no hazard is in reach).
6. Speed = `|desired| · max(interest_raw(chosen), CONTEXT_MIN_SPEED_RATIO)` — a target directly behind a hazard makes the
   ship circle the edge at ≥ 35 % speed, never stall.

The **margin is the skim knob** (narrow = runs along the edge; wide = cautious). Boost (Swarm BURST, Razor dash and
feint lunge, Ram CHARGE) bypasses the stage: committed runs ignore hazards and can be baited into a well. Wrecks and
debris are hazards too, so ships steer round them instead of grinding along them with `move_and_slide`. The Assault
corridor still applies after everything.

**Cover points must be reachable.** Ships that stand beside a wreck (Sniper §2.11, Fighter §2.12) claim it first; the
claimed wreck is skipped above, so its skirt cannot push the ship off its own cover point. Any other hazard's skirt still
applies, so a cover candidate is rejected when it lies inside another hazard's `radius + hazard_margin`.

**Tests** — new `tests/unit/test_context_avoidance.gd` (the pure function) and dual-mode rows in
`test_enemy_dual_mode.gd`: no info → `desired` returned unchanged; all-zero danger → unchanged; a target straight
behind a well: over 4 s the ship **never enters `radius` and never drops below 35 % speed** and reaches the far side;
ship inside → first step points outward; margin 12 passes closer to the edge than margin 90 (min distance compared);
avoidance 0.5 ignores a hazard it passes tangentially that avoidance 1.0 bends round; **while boosting it flies straight
through**; chosen heading between two slots is not a multiple of 22.5°; a drifting hazard is led; **a fixture wreck
claimed by the mover's actor is ignored, the same wreck claimed by another node is avoided, and an `arrive()` to a point
`radius + 50` from the claimed wreck settles within 10 px** (dual-mode); Assault: corridor still bounds the result.
Behaviour rows with real brains: a Swarm Drone patrolling past a well skims its edge; a Fighter approaching through a
well's path goes round; a Swarm BURST across the core is captured (R6.11 bait). Every existing Ph2–Ph5 behaviour,
budget, deadline and density row stays green unchanged. **Allowance: +3.5 s.**

### 2.5 Gravity Well (t6)

Scene `assault/scenes/hazards/gravity_well/gravity_well.tscn`: `HazardField` root (`kind = &"gravity_well"`) +
animated sprite (t5 art, `assault/assets/sprites/hazards/`) + `HAZARD.md`. Starting values: `radius` 420, `core_radius`
90, `pull_force` 520, `damage_radius` 150, `stress_damage` 5, `stress_period` 0.5 (10 /s), `avoid_weight` 1.0, no cycle,
`duration` 0. Field strength: 520 px/s² at ≤ 90 px, 334 at 140, 234 at 200, 131 at 357, 0 at 420. No physics body:
ships and shots pass through, and it does **not** block line of sight. Telegraph: a faint ring at `radius` drawn in
`_draw()`; an inner glow scaled by the field strength at the player's position (read-only presentation script); a
stressed ship flashes from its normal hit path. Its `HazardInfo` carries the Ram's claim (§2.14).

**Tests** — new `tests/integration/test_gravity_well.gd`, dual-mode where enemies are involved, using the real scene:
stress lands on a real Swarm Drone and on the player inside 150 px and **not at 151 px** (centre distance);
**a real Swarm Drone left inside `core_radius` with no burst stays within `damage_radius` (150 px) for 3 s and dies to
stress** (dual-mode); a real Fighter seeking outward from 100 px gets out (dual-mode); the Open Space player with thrust
held outward from 100 px does not get out, with boost it does; a plated Ram is not damaged by stress while a plate
lives; the scene passes the transparency sweep. **Allowance: +2 s.**

### 2.6 Energy Anomaly (t7)

Scene `assault/scenes/hazards/energy_anomaly/energy_anomaly.tscn`: `HazardField` root (`kind = &"anomaly"`) + a small
presentation script on the sprite only. One rule — a **pulsed sideways swirl** on ships and opted-in projectiles
(R6.12, judgement: research found no citable source; one rule per hazard, telegraph that escalates). Starting values:
`radius` 300, `core_radius` 80, `tangential_force` 260 (**an instance swirls the other way by setting −260**; there is no
`clockwise` export and t7 does not edit `hazard_field.gd`), `pull_force` 0, no damage, `cycle_telegraph` 1.0,
`cycle_active` 2.5, `cycle_quiet` 3.0, `avoid_weight` 0.7 (0 while QUIET, kept while TELEGRAPH — `HazardField` does
this). Readability: violet / magenta palette (cyan means shield in IDEAS §21.1), rings brighten through TELEGRAPH and
spin during ACTIVE, dim when QUIET — driven by `phase_changed` and `phase_progress()`.

How a ship feels it: `EnemyMover` integrates `Hazards.accel_at(pos)` (radial + tangential) into its drift (§2.2 step
5, after the accel limit, scaled by `1 − hazard_resistance`); the Open Space player adds the same accel to its velocity.

**Tests** — new `tests/integration/test_energy_anomaly.gd`: **dual-mode**: a resistance-0 mover (a fixture enemy in the
mode's harness) held at 150 px is displaced perpendicular to the centre direction (dot product with radial < 10 % of
the tangential component) during ACTIVE and the side flips with a negative `tangential_force`; **QUIET and TELEGRAPH
displace nothing**; TELEGRAPH always precedes ACTIVE; `avoid_weight` is 0 while QUIET and 0.7 while TELEGRAPH
(`HazardInfo` level); the Open Space player is swirled while ACTIVE; transparency sweep. **Allowance: +1.5 s.**

### 2.7 Projectiles in fields (t8)

Rule: **heavy, guided ordnance bends; bullets fly true** (owner default 1). A family opts in by answering
`hazard_pull_scale() -> float` (1.0) and, in its own `_physics_process`, when `Hazards.count() > 0`, rotating its
heading toward `heading · speed + Hazards.accel_at(pos) · delta` **without changing its speed** — so every time and
distance cap still holds (a distance cap from the origin can only be reached later on a curved path). Opted in: enemy
rockets (`EnemyRocket`, all five kinds, `_heading`), `EnemyOrdnance` gravity and pursuit bombs (not mines — Ph4's mine
arithmetic stays valid; `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`), player homing and warhead
missiles (their own `rotation` writer). Not opted in: `EnemyBullet` rounds, the player `Bullet`, mines, beams.

**Tests** — new `tests/integration/test_hazard_projectiles.gd`: each opted-in family fired past a fixture well bends
toward it (signed lateral offset > 0) with speed unchanged; **a round and a player bullet do not bend**; with no hazard
the path is bit-identical; the lifetime still ends a bent rocket. `test_enemy_bullet_lifetime.gd` and
`test_player_bullet_lifetime.gd` unchanged. **Allowance: +1 s.**

### 2.8 Wreck family: inert wrecks, debris, placed structures (t10)

Folder `assault/scenes/hazards/wreck/`. `Wreck` (`wreck.gd`, `CharacterBody2D`), moved by its own position writes
(the `SmallAsteroid` drift precedent; it is not an enemy, so the mover rule does not apply):
- **Body** on layer 1 (`ENVIRONMENT`), mask 0, group `wrecks`; `blocks_line_of_sight() -> bool` returns `blocks_los`
  (true for every `Wreck`), so `LineOfSight.clear()` already stops at it.
- **Shots:** a `HurtBox` (layer 512, mask 96) with `Health` covering the body (the hurtbox-geometry rule), so player
  bullets, player rockets and enemy rockets stop on it (enemy rocket impact masks 640 include 512). Not in `enemies`,
  never scored, never a homing target. **Enemy rounds stop on it too** (two-sided cover): `EnemyBullet`'s HitBox mask
  gains 1024, and `_on_hit_box_area_entered(area)` expires only if the area is not on 1024 **or** its owner answers the
  duck-typed `stops_enemy_rounds() == true` — the wreck's contact box does, an asteroid's does not, so asteroid
  behaviour is unchanged. **The player's beam** (`beam_behavior.gd:59-76`) stops at any layer-1 body and damages only
  groups `enemies` and `asteroids`: a wreck blocks the mining laser and cannot be cut by it. That is intended (it is
  cover) and is written in the wreck's `HAZARD.md`.
- **Contact:** `ContactHitBox` on 1024 (`hazard_contact`), damage 10, sharing the body's shape and scale (the
  contact-geometry rule). Player and enemy hurtboxes already mask 1024. **Only a moving wreck or debris hurts on
  contact:** a ship body (player r 11, hurtbox r 5) is stopped by the wreck's body before its hurtbox can reach a box the
  size of that body, so a stationary wreck or placed structure is solid but harmless, and a drifting wreck that runs into
  a ship hurts it. **Arming delay:** the contact box spawns with `monitorable = false` and is armed
  (`set_deferred("monitorable", true)`) `contact_arm_delay` 0.6 s after `_enter_tree()`, so a wreck born where a ship
  died against the player does not hurt the player at once.
- **Hazard:** registers with `Hazards`; `HazardInfo` `kind = &"wreck"`, `radius` = body radius, `avoid_weight` 0.6,
  `velocity` = drift, `line_of_sight_blocker` = `blocks_los`, no forces. `try_claim(node)` / `release(node)` delegate to
  the info (one cover user at a time, F9 / F11).
- **Lifetime** (one owner): exports `drift_velocity`, `lifetime` (0 = permanent), `assault_drift` (60 px/s down).
  Open Space: frees after `lifetime` 40 s, fading over the last 2 s. Assault (`EnemyWorld` reports an arena): velocity
  is `(drift_velocity.x, assault_drift)` — the inherited **x** only, so a wreck always drifts down at 60 px/s and
  crosses the whole world rect (y −444…1164, 1608 px) in ≤ 26.8 s — and it frees when `ProjectileLifetime` (world rect +
  a **30 s** cap) emits `expired`.
- **`retire()`**: unregisters, sets the body's and both areas' layers to 0 at once (deferred where inside a flush),
  fades `modulate.a` to 0 over 0.5 s, then `queue_free()`. Used by the alive-cap eviction (t11) and the Open Space
  lifetime end (fade 2 s there), so a wreck never vanishes on screen without a fade.
- Sizes: `wreck_small.tscn` (~40 px), `wreck_medium.tscn` (~72 px), `wreck_large.tscn` (~110 px); HP 200.
  **Placed structures** `structure_satellite.tscn`, `structure_cargo_platform.tscn`, `structure_station_module.tscn`:
  same script, `lifetime` 0, no drift, HP 800.
- `DebrisFragment` (`debris_fragment.gd`, `Area2D`, not a body, not a LOS blocker): contact `HitBox` on 1024,
  `speed`, `deceleration`, `spin`, `lifetime` via `ProjectileLifetime` (0 = permanent); `HazardInfo` `kind =
  &"debris"`, `avoid_weight` 0.4; optional `source: Node` + `source_clear_radius` (contact box disarmed until the
  fragment's centre is farther than `source_clear_radius` from a still-valid source — used by the Ram's fragment, §2.13).
  Scene: `debris_drift.tscn` (reuses `assault/assets/sprites/environment/debris_1..6.png`, 20–40 px/s, life 30 s,
  contact 8). The Ram's fragment scene is t15's.
- `Wreck` and `DebrisFragment` carry `spawn_into(container, at, rot)` / `_attach` / `_enter_tree` exactly as
  `HazardField` does (deferred attach on the spawned node itself; frees itself if the container is gone).
- `WreckScenes` (static): `scene_for(size: int, explosive: bool) -> PackedScene` (`explosive` returns null until t12).

**Tests** — new `tests/integration/test_wreck.gd` (8× clock where physics is needed): `LineOfSight.clear` across a
wreck is false and across a `DebrisFragment` true; a player bullet and an enemy rocket stop on a wreck; **an enemy round
stops on a wreck but still passes an asteroid**; a wreck's HP drops to 0 under fire and it frees; **a drifting wreck
pushed into the player and into an enemy hurts both, a stationary one touched by a moving player does not, and a wreck
spawned overlapping the player does not hurt it during its first 0.6 s**; a wreck in an Assault harness drifts down at
60 px/s whatever its inherited y velocity and frees on leaving the world rect, in Open Space after `lifetime`; **a wreck
drifting onto the Assault player at the clamp edge never holds the player for more than 2 physics frames** (if it does,
the wreck yields: it stops drifting into a body it touches); `retire()` unregisters at once and frees after the fade;
`spawn_into` on a freed container leaves no orphan; registered while alive, unregistered after free; never in group
`enemies`. The hurtbox-geometry, contact-geometry, transparency, collision-layer and UID gates cover the new scenes (add
them to the rosters where those gates use a hand list). **Allowance: +3 s.**

### 2.9 Wrecks from deaths and the level-1 exit guard (t11)

`ShipConfig` gains (group `Hazards`) `wreck_chance := 0.0` and `wreck_size := 0` (0 small, 1 medium, 2 large) — flat.
`BaseEnemy._on_health_changed`, on death, beside `_explosion_effect.explode()`, calls `_maybe_leave_wreck()`: if
`Hazards.container(get_tree())` exists, `config.wreck_chance > 0`, and the brain's `rng.randf() < wreck_chance`, it
instantiates `WreckScenes.scene_for(wreck_size, false)`, sets `drift_velocity` = 25 % of the ship's velocity, and calls
**`wreck.spawn_into(container, global_position, rotation)`** — deferred, because a real kill runs inside the bullet's
`area_entered` flush. Position, rotation and velocity are captured at the call; the rng draw happens at the call (so the
draw order is the same as a synchronous design). **No container → no roll at all** (no rng draw, so seeded tests are
unchanged). Legacy enemies (no brain) leave none.

**Alive cap**: Open Space 8, Assault 4 (`EnemyWorld` tells the mode). Enforced when a wreck **enters** the container
(in `Wreck._enter_tree` / `_ready`, counting the container's children in group `wrecks` that are not retiring), so two
deaths in one frame cannot slip past it; over the cap the oldest (lowest spawn sequence number, a static counter) is
`retire()`d — faded, not deleted on screen.

Starting chances: Swarm 0, Razor 0, Fighter 0.2 small, Gatling 0.2 small, Sniper 0.3 small, Support 0.3 small,
Missile Corvette 0.5 medium, Ram 0.5 medium, Bomber 0.6 large.

A `HazardContainer` (`Node2D`, group `hazard_container`) is added to `assault/scenes/levels/edelia/1/level_1.tscn` and
`open_space/scenes/levels/sector_hub.tscn`. Level 2 and the station fight get none this phase (no wrecks there).

**Level-1 exit guard (M9).** The level-1 deadline and density gates build their own containers without a
`HazardContainer`, so they cannot see wrecks by construction, while live cloud_descent will have drifting wreck bodies
(layer 1, collided by every enemy's `move_and_slide`) and avoidance danger in its exit paths; its 73.2 s Ram row has
0.40 s of margin (DECISIONS Ph4). New test in `tests/integration/test_level1_fighter_exit.gd`:
`test_cloud_descent_clears_in_time_with_wrecks_left_behind` — the file's existing 20 s replay (cloud_descent from 66.0 s:
both fighter waves, both drone waves, the 72 s Ram), plus a `HazardContainer` in the world, `wreck_chance = 1.0` set on
every spawned enemy's private config in the container's `child_entered_tree` handler, and **every fighter killed
(`health.decrease(max_health)`) on its first EXTEND entry** — mid-corridor, the worst case, leaving small wrecks in the
drones' and the Ram's paths. Asserts: at least 2 wrecks existed; the enemy container is empty within the section's
`enemies_cleared_timeout` (10.0 s) of `waves_complete`; the Ram leaves in DISENGAGE with no `EnemyPathMover`; no wreck
was ever a child of the enemy container. If it fails, the pre-approved levers, in order: (1) Assault wreck
`avoid_weight` 0.3; (2) Assault `wreck_chance` halved for every enemy; never raise `enemies_cleared_timeout`.

**Tests** — new `tests/integration/test_wreck_spawning.gd`, dual-mode: same seed → same wrecks over 20 kills; chance 0 →
none; **no container → no wreck and no rng draw** (the brain's next `randf()` equals the control's); cap retires the
oldest (Assault 4, Open Space 8), **also when two die in the same frame**; the wreck is a child of the container,
**never of the enemy container**, never in `enemies`; a director-style check: an `ENEMIES_CLEARED` container empties
while wrecks remain alive. **Real-physics row (8× clock, Open Space harness):** a real player `Bullet` fired into a real
Swarm Drone with `max_health` 1 and `wreck_chance` 1 kills it inside the bullet's `area_entered` flush, and exactly one
`Wreck` appears in the container within 3 physics frames, with no engine error (GUT fails the test on one). Plus the
exit-guard row above. Every other level-1 replay and gate stays green unchanged. **Allowance: +6 s** (≈ 3.3 s is the
exit-guard replay; report it separately).

### 2.10 Explosive wrecks and reactor fields (t12)

Scenes `wreck/wreck_explosive.tscn` (`Wreck` with `explosive = true`, HP 20, a `StateLight` that glows CHARGING-orange)
and `assault/scenes/hazards/reactor_field/reactor_field.tscn` (`HazardField`, `kind = &"reactor_field"`, `radius` 90,
`damage_radius` 90, `stress_damage` 4 every 0.5 s (8 /s), `duration` 2.0, `avoid_weight` 1.0, no pull). `ShipConfig`
gains `explosive_wreck_chance := 0.0` (the share of an enemy's wrecks that are explosive; Bomber 0.5, Missile Corvette
0.5 — ordnance carriers, the readable reason), drawn from the same `rng` right after the wreck roll (only when the wreck
roll succeeded); `WreckScenes.scene_for(size, true)` returns the explosive scene.

**Detonation**: when its HP reaches 0, or `fuse` 1.0 s after a ship's hurtbox first overlaps its armed contact box (the
light blinks during the fuse). `_detonate()` is idempotent (a `_detonated` flag) and does, in order:
1. **Blast by centre distance**: `Hazards.pulse_damage(get_tree(), global_position, 110.0, 25)` — the player and every
   enemy whose centre is within 110 px take 25 (a plated Ram deflects it; an `EnemyShield` does not absorb it; asteroids
   and other wrecks are not hit). No blast area is created, so there is nothing to add during a flush.
2. a reactor field via `reactor_field.spawn_into(container, global_position)` (deferred; no container → none);
3. `queue_free()`.
The blast hurts **everyone** (owner default 4). This decides one slice of the friendly-fire question Phase 5 left to
Phase 8: **environmental blasts hurt both sides**; enemy weapon blasts (rockets) keep their Ph5 rules and remain Ph8's
decision. Logged in DECISIONS Ph6 "Changes to earlier decisions".

**Tests** — extend `test_wreck.gd`: shot to 0 HP → the player **and** an enemy with centres at 110 px are hurt, **neither
at 111 px**; a plated Ram at 50 px is not damaged; touch → detonates after 1.0 s, not before; detonating twice in one
frame hurts once; leaves one reactor field that stresses for 2.0 s and frees; **real-physics row (8× clock):** a real
player bullet kills an explosive wreck and exactly one reactor field appears with no engine error; explosive share is
seeded (same seed, same mix); transparency sweep. **Allowance: +2 s.**

### 2.11 `can_see_player()` and the Sniper fires from cover (t13)

`EnemyBrain.can_see_player() -> bool`: `TargetInfo.line_of_sight(actor.global_position, space, [actor RID])` toward
`TargetInfo.player(tree)`; false with no player; physics-step only (the brain tick is). Existing Sniper / Support Ship
calls may stay.

Sniper (`assault/scenes/enemies/sniper/sniper_brain.gd`, `choose_firing_point()`, `:398`). Today it generates seven
jittered seed bearings plus `random_candidates` uniform ones round the player at the preferred range, filters (Assault
rect, path clearance, forward cone), sorts by tier then score `w_sep · clamp(delta / π) − w_travel · travel / (2 ·
range)`, and takes the first candidate with a clear line, at most `max_los_rays` rays. Changes, all gated on
`Hazards.count() > 0` so the no-hazard path is unchanged:
- (a) **reject candidates inside a non-wreck hazard**: `info.contains(point, hazard_margin)` for any info whose
  `line_of_sight_blocker` is false (wells, anomalies, fields) — the candidate is filtered out like a `rect_ok` failure;
- (b) **cover candidates**, appended after the normal ones and drawing **no rng**: for each info with
  `line_of_sight_blocker`, within `cover_search_radius` (700) of the sniper, free or already claimed by this actor: the
  point on the wreck's far side from the player at `radius + cover_gap` (50), then stepped sideways along the tangent in
  30 px steps (max 4, alternating sides) until `LineOfSight.clear` to the player is true ("peek"; counts against
  `max_los_rays`); kept only if its distance to the player is within `[0.65, 1.35] × range_` and it is outside every
  *other* hazard's `radius + hazard_margin`. They pass the same filters, tiers (by their own bearing) and scoring;
- (c) a **`w_cover` bonus** added to the score of a candidate within `cover_radius` (140) of a blocker, equal to `w_sep`
  (F8's partial-cover relation);
- (d) **claim**: when `_set_target_point()` takes a cover candidate it calls `try_claim(actor)` on that wreck's info
  (a refused claim → take the next survivor); the claim is released on BREAK_CONTACT entry, on DISENGAGE, and implicitly
  when the sniper is freed. While claimed, the mover's avoidance skips that wreck (§2.4), so the sniper can reach and
  hold the point;
- (e) **re-pick hysteresis, cover only** (F10): when the travel cap forces a re-pick (`_travel`, `:349`) and the current
  target is a cover point whose wreck still exists and whose line is still clear, keep it unless the new best's score
  exceeds the current point's score + `cover_hysteresis` (absolute, default `0.15 · w_sep`). Applies to nothing else;
  tier A/B relocation picks are untouched.
New flat `SniperConfig` fields: `cover_search_radius`, `cover_gap`, `cover_radius`, `w_cover`, `cover_hysteresis`.
**With no hazard registered, the pick and every rng draw are identical to today.**

**Tests** — extend `tests/integration/test_sniper.gd` (dual-mode) and `tests/unit/test_line_of_sight.gd`:
`can_see_player()` false with a wreck between, true with a `DebrisFragment` between, false without a player; with one
wreck near, the chosen firing point lies within `cover_radius` of it on the far side from the player and has a clear
line; **with none, the same point and the same next `rng.randf()` as the control**; a candidate inside a well is never
chosen; a second sniper is refused the claimed wreck and picks elsewhere; **a real sniper reaches its cover point and
holds it through SETTLE into AIM with the avoidance stage active** (`own_velocity()` below `settle_epsilon` within
`SETTLE_CAP`); the sniper refuses to fire through a wreck that drifts across the locked line; cover-only hysteresis keeps
a cover point against a better-by-less-than-the-margin plain candidate and **never changes a no-wreck pick**; the
Missile Corvette still fires with a wreck between (§28); the Sniper's attack-in-budget rows stay green.
**Allowance: +3 s.**

### 2.12 The Fighter waits behind a wreck before its pass (t14)

`assault/scenes/enemies/fighter/fighter_brain.gd` (1,650 lines; gated by the 168-layout squad sweep). Today a pass is a
bearing `b`, run direction `u = −b` and lane `l`; its start `S = P̂ + b·standoff + l` is re-derived by `_derive_pass()`
every tick until RUN_IN latches it, and APPROACH flies a Dubins lead-in to S. A squad member holds at S (which moves with
the player) for the squad window; a solo fighter never holds (`_waits_for_window()` is `_in_squad()`).

**Design: cover is a separate phase before APPROACH; the pass machinery is not touched.** Moving S was rejected: S, `b`,
`l` and `_run_heading` are derived together every tick from the anchor, and a moved S would describe a run that no longer
passes the player at its lane. Instead:
- New phase **`COVER`**, appended to `enum Phase` (after RETURNING, so no value moves). Entered from APPROACH's first tick
  (from spawn, NOTICING, or a REPOSITION that hands to APPROACH — every place APPROACH is entered) when **all** hold:
  `Hazards.count() > 0`; the fighter is solo or its squad role is `LEAD` (S15: FLANK / REAR never take cover);
  `forced_pass_kind < 0`; it has not used cover since its last RUN_IN (`_cover_used`, cleared on RUN_IN entry); in
  Assault `budget.remaining() >= config.cover_min_budget` (6.0 s); and a wreck info (`kind == &"wreck"`,
  `line_of_sight_blocker`) lies within `cover_search_radius` (500) of the fighter, is not inside another hazard's
  `radius + hazard_margin`, and `try_claim(actor)` succeeds (nearest first). Otherwise APPROACH runs exactly as today.
- In COVER the cover point is `C = W + (W − player).normalized() · (radius + cover_gap)` (`cover_gap` 40), recomputed
  every tick (it stays on the far side as the player moves); the brain calls `mover.arrive(C, config.max_speed)` and
  `mover.face_toward(player)`. The claimed wreck is skipped by avoidance (§2.4), so the fighter reaches C.
- COVER ends (→ `_cover_used = true`, release the claim, `enter_phase(Phase.APPROACH)`; APPROACH then derives the pass
  from where the fighter is, as it always does) on the first of: held within 30 px of C for `cover_hold` (1.2 s) while
  `can_see_player()` is false; the player within `cover_break_range` (300 px) of the fighter; the wreck freed or retiring;
  `cover_max` (5.0 s) since COVER entry. Budget expiry in COVER behaves as in APPROACH (DISENGAGE that tick), so the
  engagement-deadline arithmetic is unchanged.
- A squad LEAD in COVER is not at its S: its FLANKs hold at their own S as today and, by the existing rules, go after
  `flank_wait_max`; COVER only delays the LEAD's window by at most `cover_max`.
- Weapons: no burst in COVER (the leg-A/leg-B rules already restrict bursts to RUN_IN/EXTEND/TURN).
- `phase_changed` is emitted for COVER; the fighter's `ENEMY.md` phase list gains it.
New flat `FighterConfig` fields: `cover_search_radius`, `cover_gap`, `cover_hold`, `cover_break_range`, `cover_max`,
`cover_min_budget`. **With no hazard registered the brain never enters COVER and draws no extra rng**, so every row of
the 168-layout squad sweep, the fighter pin / density / exit / deadline rows and every Ph3 fighter spec must be
bit-identical (none of them has a wreck).

**Tests** — extend `tests/integration/test_fighter.gd` (dual-mode): with a wreck between a solo fighter and the player,
the fighter enters COVER, **reaches C and holds within 30 px of it with the avoidance stage active**, and
`can_see_player()` is false during the hold, then it enters APPROACH and its RUN_IN starts within `cover_max +` its usual
lead-in; the player closing within 300 px breaks cover at once; **two solo fighters with one wreck: only one takes
cover**; a squad FLANK never enters COVER, the LEAD does; the wreck freed mid-hold → APPROACH next tick; Assault with
less than `cover_min_budget` left → no COVER; with no wreck the phase sequence and positions are identical to the control
over a full pass. The 168-layout squad sweep, fighter attack-in-budget and deadline rows stay green unchanged.
**Allowance: +3 s.**

### 2.13 Debris Charge: broken ram plates fly off (t15)

`RamCorvette._on_plate_broken(plate)` (`assault/scenes/enemies/ram_corvette/ram_corvette.gd:138`) captures the plate's
global position, rotation and texture **at once** (the plate sprite is still valid at `broken.emit`,
`armor_plate.gd:145-153`), instantiates `ram_fragment.tscn` (a `DebrisFragment` in `assault/scenes/hazards/wreck/`) and
calls `fragment.spawn_into(Hazards.container(tree), at, rot)` — deferred, because a plate breaks inside the rocket's
`area_entered` flush. No container → nothing. The fragment is thrown along
`(plate.global_position − ram.global_position).normalized()` at 200 px/s, decelerating at 120 px/s², spinning, life 3.0
s, contact damage 12, `blocks_los` false. **It never hits its own Ram:** `source = ram`, `source_clear_radius` = the
Ram's body radius + the fragment's radius; its contact box stays disarmed until it is farther than that from the Ram
(or the Ram is freed). The third plate's break exposes the hull (`_expose`, deferred), and the enemy hurtbox mask (1121)
includes 1024, so without this the fragment would hit the newly exposed Ram. The plate itself breaks exactly as today
(it resolves each hit once). Passive only (owner default 3); the deliberate plate throw is not built.

**Tests** — extend `tests/integration/test_ram_corvette.gd`: a plate broken (hand path) spawns exactly one fragment
moving away from the hull; **real-physics row (8× clock):** a real player rocket (or `EnemyRocket` impact, which Ph5
lets hurt plates) breaks a plate inside its flush and exactly one fragment appears with no engine error; **breaking the
third plate exposes the Ram and its own fragment deals it no damage**; the fragment hurts the player on contact once
armed and frees itself by 3.0 s; the plate still resolves once (existing rows); no container → no fragment and every
existing ram row unchanged. **Allowance: +2 s.**

### 2.14 The Ram drives the player toward a well (t16)

`assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd`. Today APPROACH (`_tick_approach`, `:317`) is a plain
`mover.intercept(...)` in Open Space; only in Assault (`_corridor()` has area and `assault_side_offset > 0`) does it seek
a diagonal side station chosen once by `_choose_side()` (which may draw `rng`). LINE_UP then aims at the predicted
player (`_predicted_aim`, clamped to the corridor in Assault), WIND_UP freezes `charge_dir`, and CHARGE is a
`mover.boost`. A side choice among four diagonal stations cannot guarantee a cone toward a well, so the well tactic is a
**separate station that works the same way in both modes**:
- **Ticket**: at the top of `_tick_approach`, when `Hazards.count() > 0`, the Ram has no ticket and has not given up
  this approach (`_well_refused`, cleared on WIDE_TURN entry), it looks for the nearest `kind == &"gravity_well"` info
  whose centre is within `well_use_range` (600) of the player and calls `try_claim(actor)` (one Ram per well).
  In Assault it only tries while `budget.remaining() >= well_setup_max + config.line_up_cap`.
- **Station**: `S = P + (P − W).normalized() · well_standoff` (`well_standoff` 300 < `engage_range` 420), with `P` the
  player and `W` the well centre; in Assault `S` is clamped to the corridor rect as `_predicted_aim` clamps. **Feasibility
  check when the ticket is taken:** if the clamped `S` gives `angle(S − P, P − W) > well_cone_deg` (30°), the ticket is
  released at once, `_well_refused = true`, and APPROACH continues exactly as today.
- **With a ticket**: APPROACH `seek`s `S` (recomputed every tick) at `cruise_speed()` — the avoidance stage steers it
  round the well on the way (Ram `hazard_avoidance` 0.5) — and enters LINE_UP only when the player is within
  `engage_range` **and** `|pos − S| ≤ well_station_tolerance` (90 px). LINE_UP / WIND_UP / CHARGE are unchanged: the
  aim (Ram → predicted player) now points across the player toward the well, and the ARMOR shove (`contact_profile.gd`
  `_shove`, owner → target) pushes the player toward it. CHARGE is a boost, so the Ram ignores the well while charging.
- **Give-up and release**: release the ticket on WIDE_TURN entry, on DISENGAGE, on STAGGER, when the well leaves
  `well_use_range` of the player or is freed, and after `well_setup_max` (4.0 s) in APPROACH without reaching `S` (then
  `_well_refused = true`); a freed Ram frees its claim by itself.
- **No well**: no lookup, no rng draw, `_choose_side()` and the 73.2 s cloud_descent row untouched (no well in level 1).
New flat `RamCorvetteConfig` fields: `well_use_range`, `well_standoff`, `well_station_tolerance`, `well_cone_deg`,
`well_setup_max`. The Ram's `ENEMY.md` gains the station.

**Tests** — extend `test_ram_corvette.gd`, using the real well scene from t6: **Open Space**: a stationary player stub
at P, a well 350 px from P, the Ram spawned 900 px from P at bearings 0°, 90°, 180° and 270° from the well side: each
time `charge_dir` is within 30° of `P → W`; **with no well, the same phase sequence and `charge_dir` as the control**;
a second Ram is refused the ticket and charges as today; the ARMOR shove moves the player toward the well; the
`well_setup_max` give-up (the station made unreachable by a wall of fixture wrecks) releases the ticket and charges as
today. **Assault**: a well below the player inside the corridor → `charge_dir` within 30° of `P → W`; **boundary: a
well level with a player at the corridor's x edge, so the clamped S fails the cone → ticket refused at once and the side
equals the control's**. The Ram's attack-in-budget rows and the **73.2 s cloud_descent deadline row** (0.40 s margin)
stay green. **Allowance: +3 s.**

### 2.15 Gravity Field weapon: the Bomber's gravity bomb leaves a slow field (t17)

`EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`) `_detonate()` (its single exit,
`:234-240`): a `GRAVITY_BOMB` also spawns `assault/scenes/hazards/gravity_field/gravity_field.tscn` via
`field.spawn_into(Hazards.container(tree), global_position)` (deferred; none → nothing) at the detonation point:
`HazardField`, `kind = &"gravity_field"`, `radius` 150, `movement_penalty` 0.4, `duration` 3.5, `avoid_weight` 0.6, no
pull, no damage, a translucent ring sprite (t5) that fades over the last 0.5 s. Strongest-only and the 0.5 cap come from
`Hazards.penalty_at()`. Enemies feel `0.4 · (1 − resistance)` (their mover's slow step); the player feels 0.4 on thrust,
ceiling and boost (Open Space) or move and dash speed (Assault) — the consumers already exist. t17 runs after t8, which
also edits `enemy_ordnance.gd` (the bend).

**Tests** — extend `tests/integration/test_enemy_ordnance.gd` / `test_bomber.gd`: a gravity bomb's detonation leaves one
field at the blast point that frees at 3.5 s; mines and pursuit bombs leave none; **two overlapping fields slow by 0.4,
not 0.64**; **dual-mode:** a resistance-0.4 enemy in the field is slowed to 0.76× of its requested speed and the player
by 0.4; no container → no field and the existing ordnance rows unchanged. **Allowance: +1.5 s.**

### 2.16 Open Space hub: one tactical space (t18)

`open_space/scenes/levels/sector_hub.tscn` gains a `TacticalSpace` node (scene children, not rng draws, so every patrol
seed is unchanged) laid out as IDEAS §18.6's sketch: one gravity well at the centre, an energy anomaly 650–750 px from
it, and the three placed structures (`structure_satellite`, `structure_cargo_platform`, `structure_station_module`,
`lifetime` 0, no drift) forming a cover line 450–550 px from the well on the side facing the hub, plus 2–3
`debris_drift` pieces placed **with `speed` 0 and `lifetime` 0** (they spin in place; a placed piece never drifts away).
Candidate centre: bearing 22.5° on a 3200 px ring (between the Gatling anchor at 0° / 1500 px and the Bomber at 45° /
1700 px). Patrols chase the player while within their `lose_radius` (1300 px for the Ram and Sniper), so the player can
lead them there. The `HazardContainer` from t11 stays. Clearance rule, computed by a sweep on the real scene, never
hand-picked: for every patrol group, `distance(anchor, hazard centre) − hazard radius − worst idle offset −
perceive_radius > 100 px` for every element of the space; for every `MissionTrigger`, `PickupBase` and the player spawn,
`distance − hazard radius > 300 px`. Placed structures and debris are solid but deal no contact damage while still (only
a moving wreck hurts, by design).

**Tests** — extend `tests/integration/test_sector_hub_patrol.gd`: the clearance sweep above for every element; the
patrol seeds and positions are unchanged (existing rows); every placed debris piece has `speed` 0; the space has at least
one LOS blocker, so a real Sniper near it can be refused a line; while the space exists (`Hazards.count() > 0`) every
existing hub patrol row stays green. **Allowance: +1 s.**

### 2.17 Art (t5 hazard fields, t9 wrecks and structures)

Every image under `pixel-art-generation`: strict top-down orthographic (`view: "high top-down"`, `isometric: false`),
transparent background, saved with `./scripts/pixellab.sh`, opened and checked, then `--import`. Faction palette:
navy/black hulls, red/crimson accents, cool edge highlight (IDEAS §21); state colours: orange = armed / charging,
dark / off = destroyed.

**t5 — hazard fields** (`assault/assets/sprites/hazards/`): gravity well (accretion swirl, dark core with a bright
inner ring, ~192 px, 4–8 animation frames), energy anomaly (violet / magenta rings, distinct from the well, ~160 px,
4–8 frames, a dim and a lit state), gravity field ring (translucent, ~128 px, may be one frame scaled), reactor field
(orange-red unstable glow, ~96 px). The well's and fields' full `radius` is drawn in code as a faint ring (`_draw()`),
so the sprites stay small.

**t9 — wrecks and structures** (`assault/assets/sprites/wrecks/`): faction wrecks small (~40 px), medium (~72 px), large
(~110 px) — broken silhouettes, all lights off, scorch marks, not readable as live ships; an explosive-wreck overlay (an
exposed orange ordnance glow, 2 frames for the fuse blink); placed structures: damaged satellite (~96 px), abandoned
cargo platform (~128 px), broken station module (~128 px). Drifting debris reuses `debris_1..6.png`.

Tests: `test_entity_sprite_transparency.gd` (the scenes are under `assault/scenes/hazards/`, which it sweeps). Art tasks
produce imported PNGs (and `SpriteFrames` where animated) and a contact-sheet note in their report; the scenes that use
them are t6, t7, t10, t12, t17. **Allowance: 0 s.**

### 2.18 Docs and phase close (t19)

Invoke `updating-project-docs`: `docs/architecture/modules/global.md` gains `global/hazards/`; `assault.md` the hazard
scenes and the wreck family; `open_space.md` the tactical space; `PROJECT.md` conventions gain "hazards are sampled by
the body; the mover owns enemy drift; runtime hazards are spawned deferred into the `HazardContainer`"; `CLAUDE.md` names
the new gates (`test_hazards.gd`, `test_context_avoidance.gd`, `test_player_hazards.gd`, `test_wreck.gd`,
`test_wreck_spawning.gd`, `test_hazard_projectiles.gd`, the level-1 exit guard) and the round-stops-on-wreck rule beside
the projectile-ownership convention; `docs/enemy-roster.md` the hazard profile and wreck columns; the Fighter's, Sniper's
and Ram's `ENEMY.md` their new phase / station / cover rules; each hazard has its `HAZARD.md`; `tests/README.md` the
gate-time rows for this phase. Then close the phase: `docs/epics-done/cmug23om70001m52wqfwclf3l/` (`PRD.md`,
`SOURCES.md`, `REPORT.md`) and a `## Phase 6 - as built (<date>)` section in the idea's `DECISIONS.md` listing every
deviation and the gaps left. **Allowance: 0 s.**

## 3. Build sequence

| Key | Step | Depends on | Allowance |
|---|---|---|---|
| t1 | Registry, `HazardInfo` (with claims), `HazardField` (with `spawn_into`), `HazardDrift`, `pulse_damage` (§2.1) | — | 0.5 s |
| t2 | Enemy drift, slow and `own_velocity()` in `EnemyMover`, profile fields, brain gates (§2.2) | t1 | 1.5 s |
| t3 | Player ships feel pull and slow (§2.3) | t1 | 1 s |
| t4 | Context-steering avoidance stage, claimed-cover skip (§2.4) | t1, t2 | 3.5 s |
| t5 | Art: hazard fields (§2.17) | — | 0 |
| t6 | Gravity Well (§2.5) | t2, t3, t5 | 2 s |
| t7 | Energy Anomaly (§2.6) | t2, t3, t5 | 1.5 s |
| t8 | Rockets, bombs and missiles bend in fields (§2.7) | t1 | 1 s |
| t9 | Art: wrecks and structures (§2.17) | — | 0 |
| t10 | Wreck family (§2.8) | t1, t9 | 3 s |
| t11 | Wrecks from deaths, `HazardContainer` in level 1 and hub, level-1 exit guard (§2.9) | t2, t4, t10 | 6 s |
| t12 | Explosive wrecks and reactor fields (§2.10) | t11 | 2 s |
| t13 | `can_see_player()` and Sniper cover (§2.11) | t4, t11 | 3 s |
| t14 | Fighter COVER phase before a pass (§2.12) — **large** | t4, t11, t13 | 3 s |
| t15 | Debris Charge (§2.13) | t10 | 2 s |
| t16 | Ram drives the player toward a well (§2.14) | t4, t6, t11, t15 | 3 s |
| t17 | Gravity Field from gravity bombs (§2.15) | t2, t3, t5, t8 | 1.5 s |
| t18 | Hub tactical space (§2.16) | t6, t7, t11 | 1 s |
| t19 | Docs and phase close (§2.18) | all | 0 |

Ordering on shared files: `enemy_ordnance.gd` t8 → t17; `test_ram_corvette.gd` t15 → t16; every enemy `*_config.tres`
t2 → t11 → t13 / t14 / t16; `fighter_brain.gd` / `sniper_brain.gd` / `ram_corvette_brain.gd` t2 (gate swap) before
t13 / t14 / t16; `hazard_field.gd` only t1 (the claim and the swirl sign need no later edit). t11 depends on t4 because
its exit-guard row must run with avoidance active.

Total allowance ≈ 35.5 s against ≈ 40 s of headroom (≈ 200 s of 240 s at the end of Ph5), so the phase ends near
236 s. Each task reports before / after; a task that finds GUT above 232 s before it starts recovers time first by the
README's rules. Ph7 must start by recovering time (logged in DECISIONS).

## 4. Test plan

The per-task rows live in each §2 section, with their boundary cases.

### 4.1 Gates that must stay green unchanged

`test_enemy_mover_single_writer.gd` (no hazard writes enemy motion; brains only read `own_velocity()`),
`test_config_instance_isolation.gd` (new config fields are flat), `test_collision_layer_names.gd` (no new bit; every bit
used is already named), `test_enemy_hurtbox_geometry.gd` / `test_contact_hitbox_geometry.gd` (wreck scenes follow the
cover / shared-shape rules even though they are not enemies), `test_entity_sprite_transparency.gd`,
`test_resource_uid_integrity.gd`, `test_project_load_integrity.gd`, every Ph2–Ph5 behaviour spec, every level-1 pin,
density, deadline and attack-in-budget row, the 168-layout fighter squad sweep, every hub patrol row.

### 4.2 Why the level-1 gates do not move, and what guards the live level

The level-1 gates build their own containers without a `HazardContainer`, so no wreck, field or fragment spawns and no
extra rng is drawn; no well or anomaly is placed in level 1. The live level gets wrecks and fields, which never enter
the enemy container; the one row that runs cloud_descent **with** wrecks is t11's exit guard in
`test_level1_fighter_exit.gd` (§2.9).

### 4.3 Physics-callback spawns

Every runtime spawn is deferred through `spawn_into` (§2.1). Hand-ticked rows that kill through `health.decrease` run
outside a physics flush and cannot see a synchronous-add error, so each spawning task has one **real-physics** row on
the 8× clock: t11 (a real bullet kill leaves exactly one wreck), t12 (a real bullet detonates an explosive wreck and
leaves one reactor field), t15 (a real rocket breaks a plate and leaves one fragment).

### 4.4 Registry hygiene and harness coverage

Hazard tests use `add_child_autofree`; `scripts/check-test-leaks.sh` clean after t1, t10, t11. **Both harnesses**
(R6.19), each row marked dual-mode in its section: pull on enemies (t2, t6), pull on the player (t3, t6), avoidance per
profile and cover reachability (t4), anomaly swirl (t7), wreck spawning (t11), LOS blocking and cover (t10, t13, t14),
Ram well station (t16, per-mode rows), Gravity Field slow on an enemy (t17).

## 5. Risks

| Risk | Mitigation |
|---|---|
| The mover stage changes every enemy's motion | Pass-through rows bit-identical with no hazard and with a far hazard, the −0.0 case included (t2, t4); early-out on `count() == 0`; the zero-drift add is skipped |
| Context steering snaps or sticks (Godot forum report, F1/F2) | 16 slots, interpolation, distance-scaled danger, previous-direction blend, min speed ratio; "target behind a well" row |
| A ship cannot reach its own cover | Claimed LOS blockers are skipped by avoidance; reach-and-hold rows for Sniper and Fighter with avoidance active |
| A well becomes a magnet (F7) | Short reach (420 px), softened 1/r core, capture designed per ship (§2.2 table) |
| Drift breaks "stopped" checks in brains | `own_velocity()` for the named gates; Ram LINE_UP-inside-a-well row |
| Spawns refused inside a physics flush | `spawn_into` deferral everywhere; three real-physics rows (§4.3) |
| Gate time (phase ends ≈ 236 s of 240 s) | Allowances sum to 35.5 s; before / after on every task; recover-first rule at 232 s; Ph7 recovers time first |
| Wrecks crowd or stall Assault | Cap 4 with fade-out, drift off in ≤ 27 s; t11's exit-guard replay with pre-approved levers |
| Wreck physically pins the Assault player at the clamp | Wrecks move by position writes like small asteroids; t10 row: a wreck pushed onto the player at the edge does not hold them for more than 2 frames, else the wreck yields |
| Enemy rounds stopping on wrecks changes balance | Only wrecks opt in (`stops_enemy_rounds()`); asteroids unchanged |
| Fighter COVER disturbs squads | Only solo fighters and LEADs; no COVER without a wreck, so the 168-layout sweep is bit-identical; t14 is large and gets its own plan review |
| Ram well logic touches the thin 0.40 s deadline row | No well in level 1; no lookup without a well; t16 re-runs the row |
| Static registry leaks between tests | Freed nodes always unregister in `_exit_tree`; `count()` row; autofree convention |
| Feel is untested by a human | Stated in the dossier; every value is a starting value |

## 6. Out of scope

Mines and minefields (Ph7); laser emitters, barriers and walls (Ph8); jammers, EMP zones and any consumer of
`disables_abilities` (Ph9); capital-ship and boss wrecks, modules remaining as wreckage (Ph19); carrier escort and hacker
positioning tactics (Ph10/18, Ph9); hazards acting on rail-driven spawns (Ph15), the Gunship (Ph10) and the station
(immovable; Ph11/19); placed wells or anomalies in Assault levels (Ph15); cover for squad wingmen and squad-coordinated
cover (Ph14, squad communication); a designed gravity slingshot (nothing asks for one); the anomaly's shield or
targeting variants and the Ram's deliberate plate throw (owner questions 2 and 3 — each is one task on top of this phase
if wanted); friendly fire from enemy weapon blasts (Ph8); hazard audio (Ph17); encounter composition around hazards
(Ph13/14); difficulty scaling of hazard values (Ph16).

## 7. Requirements coverage

| Req | Requirement (short) | Delivered by |
|---|---|---|
| R6.1 | `HazardInfo` with the seven fields | t1 |
| R6.2 | Same contract fits later hazards | t1 (duck-typed fixture row) |
| R6.3 | Hazards affect enemies by the same physics, unless resisted | t2, t3, t6 |
| R6.4 | Structure categories (wrecks, debris, satellites, cargo, station modules; wells, anomalies, reactor fields) | t9, t10, t12, t6, t7; EMP zones → Ph9; laser barriers → Ph8 |
| R6.5 | Placement forms tactical spaces | t18 |
| R6.6 | Enemies perceive through the same system; accidental hits; pushing the player | t1, t4, t10 (moving-wreck contact), t16 |
| R6.7 | Soft avoidance layer; context-steering decision | t4 (context steering chosen) |
| R6.8 | Strength per hazard and profile; committed rammer ignores | t2 (profile fields), t4 |
| R6.9 | Hazards as tools: sniper, fighter, ram, drone skim | t13, t14, t16, t4 (skim); carrier / hacker → Ph10/18, Ph9 |
| R6.10 | Well: radial pull growing to the centre; ships and projectiles | t1, t2, t3, t6, t8 |
| R6.11 | Avoid, skim, resist, dragged, hull stress, bait | t2, t4, t6 |
| R6.12 | Energy Anomaly, readable | t7 (swirl variant; shields / targeting → owner option, out) |
| R6.13 | Wrecks: cover, collision, drifting debris, explosive; capital wreck | t10, t11, t12; capital → Ph19 |
| R6.14 | Wreck as sniper hiding spot and fighter cover | t13, t14 (solo / LEAD; wingmen → Ph14) |
| R6.15 | Gravity Field weapon | t17 |
| R6.16 | Debris Charge | t15 (passive; active throw → owner option, out) |
| R6.17 | `can_see_player()`; terrain occlusion | t10, t13, t18 |
| R6.18 | Strict top-down art per hazard | t5, t9 |
| R6.19 | Deterministic tests in both harnesses | every task's rows; §4.4 |

## 8. Response to feedback (round-1 review, `4-review.md`)

| # | Point | What changed |
|---|---|---|
| B1 | Ram well-shove hooked into Assault-only `_choose_side()` | §2.14 rewritten: a well station `S = P + (P − W)^ · 300` used by APPROACH in **both** modes (clamped to the corridor in Assault), a feasibility check that refuses the ticket when the clamped S cannot meet the 30° cone, a 4 s give-up, `_choose_side()` and its rng draw untouched without a well. Open Space rows from four bearings; an Assault feasible row and an infeasible boundary row |
| B2 | Spawns inside a physics flush | `spawn_into` / `_attach.call_deferred` on the spawned node (the `ContactBlast` pattern) defined once in §2.1 and used by wrecks (§2.9), fragments (§2.13), reactor fields (§2.10) and Gravity Fields (§2.15); the explosive blast is a distance pulse that adds no body; three real-physics rows (§4.3) |
| B3 | Cover points inside the avoidance skirt | §2.4: the avoidance stage skips a LOS-blocking hazard claimed by its own actor (claims moved onto `HazardInfo`, §2.1); Sniper and Fighter claim their wreck before travelling; reach-and-hold rows with avoidance active in §2.4, §2.11, §2.12; t13 and t14 now get §2.4 |
| B4 | Fighter cover vs `_derive_pass()` | §2.12 rewritten: a new appended `COVER` phase before APPROACH; `_derive_pass()`, the latch and the hold machinery are not touched; the pass is derived from wherever the fighter leaves cover; solo and LEAD only (S15); every squad-sweep row bit-identical; t14 marked **large** so it gets its own plan and review |
| M1 | Assault player states run in `_process`; Idle never clamps | §2.3: drift and clamp inside `player_fighter._physics_process`, after the dialog / knockback / engine-boost returns; dash gains the clamp; `hazard_speed_factor()` implemented once in `PlayerBase`; idle-player rows call `_physics_process` only |
| M2 | −0.0 + 0 flips the facing by 2π | §2.2 steps 5 and 8: the drift is added (and subtracted for facing) only when non-zero; a −0.0 row |
| M3 | Brains read drift-inclusive velocity | §2.2: `EnemyMover.own_velocity()`, the mover's `_vel()` uses it, and the five named gates switch to it; a Ram-LINE_UP-inside-a-well row |
| M4 | Hysteresis ill-defined | §2.11 (e): cover points only, absolute margin `0.15 · w_sep`; no-wreck pick and rng row |
| M5 | Explosive blast misdescribed | §2.10: `Hazards.pulse_damage` by centre distance (110 hit, 111 not); friendly-fire slice logged in DECISIONS |
| M6 | Third plate's fragment hits its own Ram | §2.13: `source` + `source_clear_radius` arming; a row |
| M7 | Stationary wreck cannot deal contact; spawn on the player | §2.8: contact only from moving wrecks (stated, rows phrased so); 0.6 s arming delay; §2.16 says placed structures are harmless while still |
| M8 | Missing ordering on shared files | §3: t17 → t8, t16 → t15, t11 → t13 / t14 / t16, t2 before every brain task; no `clockwise` export (the swirl sign is `tangential_force`), claims on `HazardInfo`, so `hazard_field.gd` is t1's only |
| M9 | No gate sees wrecks in live level 1 | §2.9: exit-guard replay of cloud_descent from 66 s with a `HazardContainer`, wrecks at chance 1 and every fighter killed mid-corridor; pre-approved levers; +3.3 s in t11's allowance |
| M10 | `planSections` gaps and bare top-level numbers | t13 / t14 gain §2.4, t7 gains §2.2; the test plan is split into 4.1–4.4 so tasks cite numbered sub-sections; top-level references use full heading text |
| M11 | Dual-mode not stated for anomaly / Gravity Field | §2.6 and §2.15 rows marked dual-mode; §4.4 lists every dual-mode row |
| M12 | Swarm core row; hub debris; Assault cap; beam | §2.5 asserts within `damage_radius` 150; §2.16 placed debris `speed` 0; §2.8 Assault y-drift fixed at 60 px/s, cap 30 s, `retire()` fades evicted wrecks; the beam note goes into the wreck's `HAZARD.md` |
