# Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields — plan

Epic `cmug23om70001m52wqfwclf3l`, plan task `cmug23oml0009m52wqy133sf2`, 2026-10-19. Built on `1-context.md` (code
inventory, requirements R6.1–R6.19) and `2-research.md` (scope check S1–S14, findings F1–F12, starting values) in this
directory, and on the idea's `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (Phases 1–5, as built). Task keys
`t1`–`t19` are the keys in `tasks.json`.

## Summary for the owner

- **For the player:** space gets terrain that matters. A gravity well drags everything in reach, you and enemies alike: small drones that blunder into its core cannot climb out and are crushed; fighters and heavy ships crawl out slowly; in Open Space you must boost out of the core. An energy anomaly pulses on a visible rhythm and, while lit, swirls ships and rockets sideways. Destroyed ships sometimes leave wrecks: hard cover that stops shots from both sides and blocks a sniper's line. Bombers' gravity bombs leave a short slowing field, and a Ram Corvette's broken armour plates fly off as dangerous fragments.
- **Enemies read the battlefield:** every new-style enemy steers round hazards with its own temperament (drones skim the edge, heavy ships are cautious and resist the pull), but any ship in a committed attack run ignores hazards and can be baited into a well. The Sniper shoots from behind wrecks, a Fighter waits behind one before its pass, and a Ram lines up so its charge shoves you toward a well.
- **Where you meet it:** the Open Space hub gains one tactical space far from the planets (a well, an anomaly, three derelict structures). Level 1 gets only what its enemies bring: wrecks, slow fields, fragments.
- **Built:** a shared hazard description and registry, pull and slow for enemies and both player ships, a context-steering avoidance stage in the enemy mover, the well, the anomaly, wrecks (inert, explosive, placed, fragments), the Gravity Field, the cover tactics, top-down art.
- **Left out:** mines (phase 7), laser walls (8), jammers and EMP zones (9), capital-ship and boss wrecks (19), hazards for legacy and rail-driven enemies (10, 15).
- **Risks:** the avoidance stage sits on every enemy's movement; tests pin that it changes nothing when no hazard is near. The test suite is near its time ceiling, so each task has a time allowance. Nothing has been play-tested; every number is a starting value.
- **Choices I made for you (tell me if you want otherwise):**
  1. Which projectiles bend in a well? *Default: rockets, bombs and your missiles; bullets fly true.*
  2. What does the anomaly distort? *Default: a pulsed sideways swirl on ships and rockets, not shields or targeting.*
  3. Debris Charge passive or active? *Default: broken ram plates fly off; no deliberate plate throw.*
  4. Does an exploding wreck hurt enemies too? *Default: yes, it is the environment, not an enemy weapon.*
  5. Wrecks in Assault? *Default: yes, at most 4 at once, drifting off the bottom.*
  6. Place a well or anomaly in level 1? *Default: no; that waits for the Assault level rework (phase 15).*

## For every task

**Scope.** Phase 6 of 20. Build only what your section names; mines (Ph7), laser walls (Ph8), jammers / EMP (Ph9),
heavy-ship and boss wrecks (Ph19) are later phases. Hazards affect **mover-driven** enemies only (the nine brains:
swarm, razor, fighter, gatling, bomber, sniper, ram, missile corvette, support); rails and legacy enemies are untouched.
**Names (new, shared — do not rename).** `global/hazards/`: `HazardInfo` (`hazard_info.gd`, `RefCounted` snapshot),
`Hazards` (`hazards.gd`, static registry), `HazardField` (`hazard_field.gd`, the one field node script),
`HazardDrift` (`hazard_drift.gd`, the pull integrator). `assault/scenes/hazards/`: `gravity_well/`, `energy_anomaly/`,
`gravity_field/`, `reactor_field/`, `wreck/` (`Wreck`, `DebrisFragment`, `WreckScenes`). Groups: `hazard_container`
(the runtime parent of spawned hazards), `wrecks`. `HazardInfo.kind` values: `&"gravity_well"`, `&"anomaly"`,
`&"gravity_field"`, `&"reactor_field"`, `&"wreck"`, `&"debris"` (later `&"mine"`, `&"laser_wall"`, `&"jammer"`).
**The model: hazards are sampled by the body.** A hazard node answers `hazard_info() -> HazardInfo` (duck type, like
`blocks_line_of_sight()`), calls `Hazards.register(self)` in `_enter_tree()` and `Hazards.unregister(self)` in
`_exit_tree()`. Bodies ask the registry: `Hazards.accel_at(pos) -> Vector2` (pull + swirl, px/s²),
`Hazards.penalty_at(pos) -> float` (strongest slow only, capped at `Hazards.MAX_PENALTY` 0.5),
`Hazards.around(pos, reach) -> Array` (infos whose `radius + reach` covers `pos`), `Hazards.count() -> int` (O(1)).
**A hazard never writes a ship's velocity or position.** No `Area2D` fields, so **collision bit 12 stays unallocated**
(revises the Ph1 roadmap; logged in DECISIONS). The only thing a hazard does to a ship directly is hull-stress damage,
a direct `HurtBox.received_damage.emit(n)` pulse (the laser-ray precedent).
**Enemies.** `EnemyMover` stays the single writer (`test_enemy_mover_single_writer.gd`). Its step becomes: desired
(boost or capped request) → × slow factor → context avoidance stage (skipped while boosting) → accel limit →
`+ drift` (pull, applies while boosting) → corridor `constraint.filter()` last → write. **Pass-through rule:** with no
hazard in reach and zero drift, velocity and rotation are bit-identical to today; `Hazards.count() == 0` must cost one
integer compare per step. Per-enemy profile is three flat `ShipConfig` fields (`@export_group("Hazards")`):
`hazard_avoidance` 0..1, `hazard_margin` px, `hazard_resistance` 0..1, copied onto the mover by `BaseEnemy._ready()`.
Committed attacks are `mover.boost()` and so ignore avoidance — never add a separate "ignore hazards" API.
**Players.** The Open Space ship adds `accel · dt` to its own `velocity` (its momentum and damping); the Assault fighter
holds a `HazardDrift` and is displaced by it before its state moves and clamps. `ShipTurnController` stays the only
writer of the Open Space ship's rotation; a pull never rotates a ship.
**Runtime spawns** (wrecks, fragments, Gravity Fields, reactor fields) go into `Hazards.container(tree)` (first node in
group `hazard_container`). **No container → spawn nothing** (this keeps every existing test and calibrated replay
unchanged). Never into the enemy container (it holds `ENEMIES_CLEARED` open, `assault/scenes/systems/level_director/level_director.gd:170`), never into group
`enemies`, never scored. Every spawned hazard frees itself (one owner): `ProjectileLifetime` emits `expired`, the
hazard connects `expired → queue_free`, or a `duration` clock frees it.
**Determinism.** Randomness only from the dying enemy's `brain.rng` (seeded); no `Timer` nodes; clocks are accumulated
`delta` in `_physics_process(delta)`, so tests hand-tick `HazardField._physics_process(d)` and drive enemies with
`test_enemy_dual_mode.gd`'s `_tick()`. Field maths needs no physics frame; only collision rows (a body hits a wreck,
a shot hits a wreck, a LOS ray) use real physics, on the 8× clock (`_scale_clock()` / `_restore_clock()` from
`tests/integration/test_level1_drone_exit.gd`).
**Tests.** Failing test first. Dual-mode specs parameterise on a label, never a harness:
`func test_x(mode: String = use_parameters(["open_space", "assault"]))`, harness built in the body from
`tests/helpers/enemy_ai_harness.gd`. Add hazard nodes with `add_child_autofree` so the static registry is empty again
after each test (a leaked hazard slows every later mover test). Read `tests/README.md` first. Run
`scripts/check-test-leaks.sh` after anything that awaits.
**Gate time.** GUT must stay ≤ 240 s (≈ 200 s at the end of Ph5). Run `scripts/gate-time.sh` before and after; report
both GUT times and stay within your section's **allowance**. Cut time only by the README's three rules.
**Coordinates.** Assault waves stay in 640×360 design units; nothing in `global/` references `ArenaCamera` (use
`EnemyWorld`). Hazard radii and speeds are world px.
**Art.** Invoke `pixel-art-generation` before any PixelLab call: strict top-down (`view: "high top-down"`,
`isometric: false`), save only with `./scripts/pixellab.sh`, open and look at every image, transparent background
(`test_entity_sprite_transparency.gd` sweeps `assault/scenes/hazards/`). Fix a painted background with
`./scripts/strip-sprite-bg.sh`. Never hand-type a `uid://`.
**Docs and log.** Each new hazard gets a `HAZARD.md` beside its scene. A deviation a later phase depends on goes into
the Phase 6 section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`. Gate: `bash /agent/verify.sh`.

## 1. Problem

Today the battlefield is empty: Open Space has no terrain at all, Assault has only asteroids, and no enemy reacts to
anything but the player. Enemies cannot be lured into danger, cannot take cover, and nothing in the world shapes a
fight. Phase 4 built a line-of-sight rule that nothing in shipped content ever blocks.

After this phase: hazards are part of one shared simulation. A gravity well pulls the player and every AI enemy by the
same field, scaled by each ship's resistance; enemies see the same hazards and steer round them according to their
profile, except in a committed run, where they can be baited in. Destroyed ships sometimes leave wrecks that block shots
and sight lines, and three enemies use hazards as tools: the Sniper hides behind wrecks, the Fighter waits behind one
before its pass, and the Ram tries to drive the player toward a well.

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

## 2. Design

### 2.1 HazardInfo, the Hazards registry, HazardField and HazardDrift (t1)

All four live in `global/hazards/`. Pure maths is static or on `HazardInfo`, so it is unit-testable without a scene.

**`HazardInfo`** (`RefCounted`). Each hazard node owns **one** instance, updates it in place (position every physics
frame for moving hazards, state on phase changes) and returns it from `hazard_info()`. Callers treat it as read-only.

| Field | Type | Meaning |
|---|---|---|
| `position` | Vector2 | centre, world px |
| `radius` | float | outer edge of every effect: pull reach, slow area, avoidance footprint |
| `pull_force` | float | radial acceleration at the core, px/s², toward the centre (0 = none) |
| `damage_per_second` | float | hull stress inside `damage_radius` (= `stress_damage / stress_period`; for the AI) |
| `movement_penalty` | float | 0..1 slow inside `radius` |
| `disables_abilities` | bool | carried for Ph9; no producer or consumer this phase |
| `line_of_sight_blocker` | bool | mirrors the body's `blocks_line_of_sight()` |
| `kind` | StringName | see *For every task* |
| `core_radius` | float | softening radius: the pull is constant inside it |
| `damage_radius` | float | hull-stress radius |
| `tangential_force` | float | swirl acceleration at the core, px/s²; sign = direction (+ = clockwise in screen space) |
| `avoid_weight` | float | 0..1, how bad entering is (well 1.0, reactor 1.0, anomaly 0.7 while lit / 0 quiet, gravity field 0.6, wreck 0.6, debris 0.4) |
| `velocity` | Vector2 | drifting hazards; avoidance leads them |
| `source` | Node | the hazard node (claims, `is_instance_valid` checks) |

Methods: `falloff(r) -> float` (the shared profile below, 0..1), `accel_at(pos) -> Vector2` (radial `pull_force` +
tangential `tangential_force`, both × falloff), `penalty_at(pos) -> float` (`movement_penalty` inside `radius`, else 0),
`contains(pos, margin := 0.0) -> bool`.

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
  null (BaseEnemy exposes `hurt_box`; verify the two player ships' node names).

**`HazardDrift`** (`RefCounted`): `velocity: Vector2`, `half_life := 0.35`,
`step(accel: Vector2, resistance: float, delta: float) -> Vector2`:
`velocity += accel · (1 − resistance) · delta; velocity *= pow(0.5, delta / half_life)`; snap to `Vector2.ZERO` below
0.5 px/s; returns `velocity`. `reset()`. Terminal drift in a constant field is `a · (1 − res) / k`, `k = ln 2 / 0.35 =
1.98 /s`.

**`HazardField`** (`Node2D`, `class_name HazardField`) — the one script behind the well, the anomaly, the Gravity Field
and the reactor field (composition: a scene sets exports and adds its sprite). Exports: `kind`, `radius`,
`core_radius`, `pull_force`, `tangential_force`, `movement_penalty`, `avoid_weight`, `damage_radius`, `stress_damage`
(int per pulse), `stress_period` (s), `duration` (s, 0 = permanent; frees itself at the end), and the pulse cycle
`cycle_telegraph`, `cycle_active`, `cycle_quiet` (all 0 = always active). Signals:
`phase_changed(phase: int)` (enum `Phase { ACTIVE, TELEGRAPH, QUIET }`), `stressed(target: Node2D, damage: int)`.
`_physics_process(delta)` advances the cycle and duration clocks, writes the live `HazardInfo` (when QUIET:
`pull_force`, `tangential_force`, `movement_penalty`, `avoid_weight` all 0; TELEGRAPH: forces 0, `avoid_weight` kept)
and, every `stress_period` while ACTIVE, emits `stress_damage` into `Hazards.hurt_box_of(ship)` for each node in groups
`enemies` and `player` within `damage_radius`. `phase_progress() -> float` for art.

**Hull stress bypasses `EnemyShield`** (it hooks `area_entered`, Ph5) — it is hull stress. The player's own damage path
treats a pulse like any other hit (a shield charge absorbs it). A plated Ram deflects it while a plate lives (its
`_on_received_damage` deflects every hit). Both stated in each field's `HAZARD.md`.

**Tests** — `tests/unit/test_hazards.gd`, `tests/unit/test_hazard_field.gd`:
register on enter / unregister on exit; **`count()` is 0 after the node is freed**; `around()` includes a hazard at
exactly `radius + reach` and excludes one 1 px beyond; `falloff`: 1 at the core, `core/r` at 2 × core, **0 at `radius`**,
**finite with zero direction at r = 0**, monotone across the taper; `accel_at` sums two wells; tangential is
perpendicular to radial and its sign flips direction; `penalty_at` **strongest only (0.4 and 0.3 → 0.4) and capped (0.8
→ 0.5)**; `HazardDrift` approaches `a(1−res)/k` within 2 % after 3 s at 60 Hz, halves with resistance 0.5, snaps to zero;
`HazardField` cycle order TELEGRAPH → ACTIVE → QUIET with the configured lengths, forces 0 outside ACTIVE, `avoid_weight`
kept during TELEGRAPH; stress pulses once per `stress_period` to a fixture enemy inside `damage_radius` and **none at
`damage_radius + 1`**; `duration` frees the node; a duck-typed fixture hazard (not a `HazardField`) joins `around()`
with no other change (R6.2). **Allowance: +0.5 s.**

### 2.2 Enemies feel the pull and the slow: EnemyMover drift and speed factor (t2)

`global/enemy_ai/enemy_mover.gd` gains three exports, `hazard_avoidance := 0.0`, `hazard_margin := 0.0`,
`hazard_resistance := 0.0` (an unconfigured mover feels full physics and avoids nothing), a private `HazardDrift`, and
`_last_drift: Vector2`. `ShipConfig` gains `@export_group("Hazards")` with `hazard_avoidance = 1.0`,
`hazard_margin = 60.0`, `hazard_resistance = 0.0`; `BaseEnemy._ready()` copies them onto `_mover` when both exist (a
field write, legal for the single-writer gate). Per-enemy `.tres` values (starting values, research §3.2):

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
4. accel / braking limit with `current = actor.velocity − _last_drift` (the ship's own velocity; skipped while boosting);
5. **drift**: `d = _drift.step(Hazards.accel_at(pos), hazard_resistance, delta)`; `v = v_self + d` — applies **while
   boosting** too (physics, R6.3);
6. `constraint.filter(pos, v)` **last**, so a well near the Assault edge never drags an enemy past the hard band;
7. write `velocity`, `move_and_slide()`; `_last_drift = d`;
8. facing from `v − d` (the ship's own heading; equals today's `v` when `d` is zero), or the face point.

`halt()` (used by `suspend_ai()`) also resets the drift and `_last_drift`. **Early-out:** when `Hazards.count() == 0`
and the drift is zero, skip steps 2, 3 and 5 entirely (one compare). Rails and legacy enemies have no mover step, so a
well never moves them.

Capture table (well of §2.5: `pull_force` 520, `core_radius` 90, `radius` 420; terminal drift `a(1−res)/1.98`):
Swarm 263 px/s drift vs 220 own speed → **captured** in the core; Razor captured at approach speed, escapes by dashing;
Fighter 236 vs 300 → escapes; Gatling 223 vs 260; Support 236 vs 270; Missile Corvette 158 vs 210; Ram 131 vs 280.

**Tests** — extend `tests/unit/test_enemy_mover.gd`; add rows to `tests/integration/test_enemy_dual_mode.gd`:
**bit-identical velocity and rotation with no hazard** for four movers (instant, accel-limited, boosting, Assault
constrained) over 120 ticks, compared against a recorded run of the same mover with the registry empty; **the same with a
fixture well registered 2000 px away**; a fixture well (`HazardField`, `pull_force` 520) drags an idle mover inward in
both modes; resistance 0.5 drifts about half as far over 1 s; **a Swarm Drone config in the core cannot leave while a
Fighter config can** (seek outward for 3 s); drift persists through a `boost()`; `halt()` zeroes it; Assault: a well
beyond the corridor's hard band never pulls an enemy past it; a fixture Gravity Field (penalty 0.4) scales a
resistance-0 mover's top speed to 0.6× and a resistance-0.5 mover's to 0.8×, boost included; an enemy on a rail
(`EnemyPathMover`) is not moved by a well. `test_config_instance_isolation.gd` stays green (flat fields).
**Allowance: +1.5 s** (includes the early-out's cost on `test_fighter_squad.gd`; report that file's time).

### 2.3 Players feel the pull and the slow (t3)

**Open Space ship** (`open_space/scenes/entities/player/player_ship.gd`). A new pure method
`_step_hazards(delta: float) -> void`, called inside `_handle_thrust()` after the thrust / damping block and before
`_step_boost()` (whose ceiling clamp therefore bounds a pull), adds `Hazards.accel_at(global_position) · delta` to
`velocity`. Skipped while `engine_boost_active` (the module owns velocity; `_handle_thrust` already returns early).
Slow: `hazard_speed_factor() -> float = 1 − Hazards.penalty_at(global_position)` scales `thrust_acceleration`,
`reverse_acceleration`, the speed ceiling and `boost_exit_speed` where they are read (never written). Rotation untouched.
Consequence: thrust (380 px/s²) cannot out-pull the well where `a > 380`, i.e. inside **123 px** of its centre — there
the player must boost (700 px/s).

**Assault fighter** (`assault/scenes/player/player_fighter.gd`). It holds a `HazardDrift`; its `_physics_process`
(which runs before its state machine's child states) steps it and displaces the ship by `drift · delta`
(`move_and_collide`), so the state's own `move()` and its hard-bounds clamp (`move_state.gd`: x [-100, 1380], y [-380,
1100]) still run last. Verify every state that moves the ship clamps (idle, move, dash); add the clamp where one is
missing. `PlayerBase` gains `hazard_speed_factor() -> float` (default 1.0); the fighter overrides it with
`1 − Hazards.penalty_at(pos)`, and `move_state.gd` / `dash_state.gd` multiply `move_speed` / `dash_speed` by it.

**Tests** — new `tests/integration/test_player_hazards.gd`: Open Space ship with no input beside a fixture well drifts
inward; **at 140 px with thrust held outward it escapes; at 100 px it does not; with boost it escapes from 100 px**;
rotation unchanged by the pull; Gravity Field (penalty 0.4) scales thrust and boost exit speed to 0.6×; Assault fighter
drifts toward a well with no input and **stays inside its clamp when the well sits beyond the edge**; its move and dash
speeds scale by 0.6 in a field; with no hazard every existing `test_open_space_*` / player row is unchanged.
**Allowance: +1 s.**

### 2.4 Soft avoidance: the context-steering stage (t4)

A pure function `Steering.context_avoid(pos, desired, infos, avoidance, margin, lookahead, prev_dir) -> Vector2` in
`global/enemy_ai/steering.gd`, called by `EnemyMover.step()` at step 3 of §2.2 (after the slow, before the accel limit)
when **not boosting**, `hazard_avoidance > 0`, `desired` is non-zero and `Hazards.count() > 0`. Infos come from
`Hazards.around(pos, hazard_margin + |desired| · lookahead)`; none → return `desired` unchanged (pass-through).

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

**Tests** — new `tests/unit/test_context_avoidance.gd` (the pure function) and rows in `test_enemy_dual_mode.gd`:
no info → `desired` returned unchanged; all-zero danger → unchanged; a target straight behind a well: over 4 s the ship
**never enters `radius` and never drops below 35 % speed** and reaches the far side; ship inside → first step points
outward; margin 12 passes closer to the edge than margin 90 (min distance compared); avoidance 0.5 ignores a hazard it
passes tangentially that avoidance 1.0 bends round; **while boosting it flies straight through**; chosen heading between
two slots is not a multiple of 22.5°; a drifting hazard is led; Assault: corridor still bounds the result. Behaviour rows
with real brains: a Swarm Drone patrolling past a well skims its edge; a Fighter approaching through a well's path goes
round; a Swarm BURST across the core is captured (R6.11 bait). Every existing Ph2–Ph5 behaviour, budget, deadline and
density row stays green unchanged. **Allowance: +3 s.**

### 2.5 Gravity Well (t6)

Scene `assault/scenes/hazards/gravity_well/gravity_well.tscn`: `HazardField` root (`kind = &"gravity_well"`) +
animated sprite (t5 art) + `HAZARD.md`. Starting values: `radius` 420, `core_radius` 90, `pull_force` 520,
`damage_radius` 150, `stress_damage` 5, `stress_period` 0.5 (10 /s), `avoid_weight` 1.0, no cycle, `duration` 0.
Field strength: 520 px/s² at ≤ 90 px, 334 at 140, 234 at 200, 131 at 357, 0 at 420. No physics body: ships and shots
pass through, and it does **not** block line of sight. Telegraph: a faint ring at `radius`; an inner glow scaled by the
field strength at the player's position (read-only presentation script, verbose-free); a stressed ship flashes from its
normal hit path.

**Tests** — new `tests/integration/test_gravity_well.gd`, dual-mode where enemies are involved, using the real scene:
stress lands on a real Swarm Drone and on the player inside 150 px and **not at 151 px**; a real Swarm Drone left in the
core with no burst stays within the core and dies to stress; a real Fighter seeking outward from 100 px gets out; the
Open Space player with thrust held outward from 100 px does not get out, with boost it does; a plated Ram is not damaged
by stress while a plate lives; the scene passes the transparency sweep. **Allowance: +2 s.**

### 2.6 Energy Anomaly (t7)

Scene `assault/scenes/hazards/energy_anomaly/energy_anomaly.tscn`: `HazardField` root (`kind = &"anomaly"`), one
rule only — a **pulsed sideways swirl** on ships and opted-in projectiles (R6.12, judgement: research found no citable
source; one rule per hazard, telegraph that escalates). Starting values: `radius` 300, `core_radius` 80,
`tangential_force` 260 (sign set per instance by an export `clockwise := true`), `pull_force` 0, no damage,
`cycle_telegraph` 1.0, `cycle_active` 2.5, `cycle_quiet` 3.0, `avoid_weight` 0.7 (0 while QUIET, kept while
TELEGRAPH). Readability: violet / magenta palette (cyan means shield in IDEAS §21.1), rings brighten through TELEGRAPH
and spin during ACTIVE, dim when QUIET — driven by `phase_changed` and `phase_progress()`.

**Tests** — new `tests/integration/test_energy_anomaly.gd`: a resistance-0 mover in the field is displaced
perpendicular to the centre direction (dot product with radial < 10 % of the tangential component) and the side flips
with `clockwise`; **QUIET and TELEGRAPH displace nothing**; TELEGRAPH always precedes ACTIVE; `avoid_weight` is 0 while
QUIET and 0.7 while TELEGRAPH (HazardInfo level); the Open Space player is swirled while ACTIVE; transparency sweep.
**Allowance: +1.5 s.**

### 2.7 Projectiles in fields (t8)

Rule: **heavy, guided ordnance bends; bullets fly true** (owner default 1). A family opts in by answering
`hazard_pull_scale() -> float` (1.0) and, in its own `_physics_process`, when `Hazards.count() > 0`, rotating its
heading toward `heading · speed + Hazards.accel_at(pos) · delta` **without changing its speed** — so every time and
distance cap still holds (a distance cap from the origin can only be reached later on a curved path). Opted in: enemy
rockets (`EnemyRocket`, all five kinds, `_heading`), `EnemyOrdnance` gravity and pursuit bombs (not mines — Ph4's mine
arithmetic stays valid), player homing and warhead missiles (their own `rotation` writer). Not opted in: `EnemyBullet`
rounds, the player `Bullet`, mines, beams.

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
  behaviour is unchanged.
- **Contact:** `ContactHitBox` on 1024 (`hazard_contact`), damage 10, sharing the body's shape and scale
  (the contact-geometry rule). Player and enemy hurtboxes already mask 1024, so ships that ram a wreck are hurt.
- **Hazard:** registers with `Hazards`; `HazardInfo` `kind = &"wreck"`, `radius` = body radius, `avoid_weight` 0.6,
  `velocity` = drift, `line_of_sight_blocker` = `blocks_los`, no forces. `claimed_by: Node` + `try_claim(node) ->
  bool` / `release(node)` (one user at a time, F9 / F11), released automatically if the claimer is freed.
- **Lifetime** (one owner): exports `drift_velocity`, `lifetime` (0 = permanent), `assault_drift` (60 px/s down).
  Open Space: frees after `lifetime` 40 s, fading over the last 2 s. Assault (`EnemyWorld` reports an arena): moves by
  `assault_drift` + its inherited velocity and frees when `ProjectileLifetime` (world rect + 20 s cap) emits `expired`.
- Sizes: `wreck_small.tscn` (~40 px), `wreck_medium.tscn` (~72 px), `wreck_large.tscn` (~110 px); HP 200.
  **Placed structures** `structure_satellite.tscn`, `structure_cargo_platform.tscn`, `structure_station_module.tscn`:
  same script, `lifetime` 0, no drift, HP 800.
- `DebrisFragment` (`debris_fragment.gd`, `Area2D`, not a body, not a LOS blocker): contact `HitBox` on 1024,
  `speed`, `deceleration`, `spin`, `lifetime` via `ProjectileLifetime`; `HazardInfo` `kind = &"debris"`,
  `avoid_weight` 0.4. Scenes: `debris_drift.tscn` (reuses `assault/assets/sprites/environment/debris_1..6.png`,
  20–40 px/s, life 30 s, contact 8) — the Ram's fragment scene is t15's.
- `WreckScenes` (static): `scene_for(size: int, explosive: bool) -> PackedScene` (`explosive` returns null until t12).

**Tests** — new `tests/integration/test_wreck.gd` (8× clock where physics is needed): `LineOfSight.clear` across a
wreck is false and across a `DebrisFragment` true; a player bullet and an enemy rocket stop on a wreck; **an enemy round
stops on a wreck but still passes an asteroid**; a wreck's HP drops to 0 under fire and it frees; contact hurts the
player and an enemy; a wreck in an Assault harness drifts down and frees on leaving the world rect, in Open Space after
`lifetime`; **a wreck drifting onto the Assault player at the clamp edge never holds the player for more than 2 physics frames** (if it does, the wreck yields: it stops drifting into a body it touches); `try_claim` refuses a second claimer and frees the claim when the claimer is freed; registered while alive,
unregistered after free; never in group `enemies`. The hurtbox-geometry, contact-geometry, transparency, collision-layer
and UID gates cover the new scenes (add them to the rosters if those gates use a hand list). **Allowance: +3 s.**

### 2.9 Wrecks from deaths (t11)

`ShipConfig` gains (group `Hazards`) `wreck_chance := 0.0` and `wreck_size := 0` (0 small, 1 medium, 2 large) — flat.
`BaseEnemy._on_health_changed`, on death, beside `_explosion_effect.explode()`, calls `_maybe_leave_wreck()`: if
`Hazards.container(get_tree())` exists, `config.wreck_chance > 0`, and the brain's `rng.randf() < wreck_chance`, it
instantiates `WreckScenes.scene_for(wreck_size, false)` at the enemy's position and rotation with `drift_velocity` =
25 % of its velocity, into the container. **No container → no roll at all** (no rng draw, so seeded tests are
unchanged). Legacy enemies (no brain) leave none. Alive cap: Open Space 8, Assault 4 (`EnemyWorld` tells the mode);
over the cap the oldest wreck (lowest spawn sequence number) is freed first.

Starting chances: Swarm 0, Razor 0, Fighter 0.2 small, Gatling 0.2 small, Sniper 0.3 small, Support 0.3 small,
Missile Corvette 0.5 medium, Ram 0.5 medium, Bomber 0.6 large.

A `HazardContainer` (`Node2D`, group `hazard_container`) is added to `assault/scenes/levels/edelia/1/level_1.tscn` and
`open_space/scenes/levels/sector_hub.tscn`. Level 2 and the station fight get none this phase (no wrecks there).

**Tests** — new `tests/integration/test_wreck_spawning.gd`, dual-mode: same seed → same wrecks over 20 kills; chance 0 →
none; **no container → no wreck and no rng draw** (the brain's next `randf()` equals the control's); cap evicts the oldest
(Assault 4, Open Space 8); the wreck is a child of the container, **never of the enemy container**, never in `enemies`;
a director-style check: an `ENEMIES_CLEARED` container empties while wrecks remain alive. Every level-1 replay and gate
(they build their own containers without a `HazardContainer`) stays green unchanged. **Allowance: +2 s.**

### 2.10 Explosive wrecks and reactor fields (t12)

Scenes `wreck/wreck_explosive.tscn` (`Wreck` with `explosive = true`, HP 20, a `StateLight` that glows CHARGING-orange)
and `assault/scenes/hazards/reactor_field/reactor_field.tscn` (`HazardField`, `kind = &"reactor_field"`, `radius` 90,
`damage_radius` 90, `stress_damage` 4 every 0.5 s (8 /s), `duration` 2.0, `avoid_weight` 1.0, no pull). `ShipConfig`
gains `explosive_wreck_chance := 0.0` (the share of an enemy's wrecks that are explosive; Bomber 0.5, Missile Corvette
0.5 — ordnance carriers, the readable reason), drawn from the same `rng` after the wreck roll; `WreckScenes` returns the
explosive scene.

Detonation: when its HP reaches 0, or 1.0 s after a ship's hurtbox first touches its contact box (the light blinks
during the fuse). The blast hurts **everyone** (owner default 4): radius 110, damage 25, delivered like the Ph5 rocket
impact (a HitBox reaching both 128 and 512, so the player, enemies, plates and asteroids), then a reactor field is
spawned into the container and the wreck frees.

**Tests** — extend `test_wreck.gd`: shot to 0 HP → blast hurts the player **and** an enemy within 110 px and **neither
at 111 px**; touch → detonates after 1.0 s, not before; leaves a reactor field that stresses for 2.0 s and frees;
explosive share is seeded (same seed, same mix); transparency sweep. **Allowance: +2 s.**

### 2.11 `can_see_player()` and the Sniper hides behind wrecks (t13)

`EnemyBrain.can_see_player() -> bool`: `TargetInfo.line_of_sight(actor.global_position, space, [actor RID])` toward
`TargetInfo.player(tree)`; false with no player; physics-step only (the brain tick is). Existing Sniper / Support Ship
calls may stay.

Sniper (`assault/scenes/enemies/sniper/sniper_brain.gd`, `choose_firing_point()`): (a) **reject candidates inside any
hazard** (`info.contains(p, hazard_margin)`, wrecks excepted as obstacles to stand behind, not in); (b) **cover
candidates**: for each info with `line_of_sight_blocker` within `cover_search_radius` (700) of the sniper, the point on
the wreck's far side from the player at `radius + 50`, then stepped sideways along the tangent in 30 px steps (max 4)
until the line to the player is clear ("peek"); they join the normal candidate list and pass the same filters (tiers,
Assault inset, cone, path clearance, LOS — it must still see to fire); (c) a **`w_cover` bonus** for a candidate within
`cover_radius` (140) of a blocker, equal to the existing separation weight `w_sep` (F8's partial-cover relation);
(d) re-pick hysteresis: keep the current point unless the new best beats it by 15 % (F10). New flat `SniperConfig`
fields: `cover_search_radius`, `cover_radius`, `w_cover`, `cover_hysteresis`. **With no blocker in range the pick is
identical to today** (no extra rng draws — the cover candidates draw nothing).

**Tests** — extend `tests/integration/test_sniper.gd` (dual-mode) and `tests/unit/test_line_of_sight.gd`:
`can_see_player()` false with a wreck between, true with a `DebrisFragment` between, false without a player; with one
wreck near, the chosen firing point lies within `cover_radius` of it on the far side from the player and has a clear
line; **with none, the same point as the control**; a candidate inside a well is never chosen; the sniper refuses to
fire through a wreck that drifts across the locked line; the Missile Corvette still fires with a wreck between (§28);
the Sniper's attack-in-budget rows stay green. **Allowance: +2.5 s.**

### 2.12 The Fighter waits behind a wreck before its pass (t14)

`assault/scenes/enemies/fighter/fighter_brain.gd`: in `_derive_pass()`, after the pass start S is chosen, if a wreck
(`kind == &"wreck"`, `line_of_sight_blocker`) lies within `cover_shift_max` (220) of S and `try_claim(self)` succeeds,
move S to the wreck's far side from the player at `radius + 40`, re-plan (`_plan` / `_best_path`, which still checks
`_segment_clears`), and hold there (`_hold_station`) while `can_see_player()` is false, up to the existing hold limit;
release the claim when the pass starts or the fighter dies. Points inside any non-wreck hazard are rejected as S.
New flat `FighterConfig` field `cover_shift_max`. With no wreck the pass is identical to today.

**Tests** — extend `tests/integration/test_fighter.gd` (dual-mode): with a wreck near S the fighter holds within
`radius + 80` of the wreck and `can_see_player()` is false during the hold, then the pass starts; **two fighters with
one wreck: only one holds behind it**; with no wreck the pass is identical to the control; the 168-layout squad sweep,
fighter attack-in-budget and deadline rows stay green. **Allowance: +2.5 s.**

### 2.13 Debris Charge: broken ram plates fly off (t15)

`RamCorvette._on_plate_broken(plate)` (`ram_corvette.gd:138`) spawns one `ram_fragment.tscn` (a `DebrisFragment` in
`assault/scenes/hazards/wreck/`) into `Hazards.container(tree)` (none → nothing) at the plate's global transform, with
the plate's texture, thrown along `(plate.global_position − ram.global_position).normalized()` at 200 px/s, decelerating
at 120 px/s², spinning, life 3.0 s, contact damage 12, `blocks_los` false. The plate itself breaks exactly as today
(it resolves each hit once; the fragment is a new object after the plate is gone). Passive only (owner default 3); the
deliberate plate throw is not built.

**Tests** — extend `tests/integration/test_ram_corvette.gd`: a rocket breaking a plate spawns exactly one fragment
moving away from the hull; the plate still resolves once (existing rows); the fragment hurts the player on contact and
frees itself by 3.0 s; no container → no fragment and every existing ram row unchanged. **Allowance: +1.5 s.**

### 2.14 The Ram drives the player toward a well (t16)

`assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` `_choose_side()`: when a `&"gravity_well"` info lies within
`well_use_range` (600) of the player and its ticket is free (`claimed_by` on the well's `HazardField` — add the same
`try_claim` / `release` pair there), prefer the side whose charge direction (Ram → player) is within `well_cone_deg`
(30) of player → well, so the charge and the ARMOR shove (`contact_profile.gd` `_shove`, owner → target) push the player
toward it. The Ram avoids the well normally while lining up (avoidance) and ignores it in CHARGE (boost). One Ram per well.
New flat `RamCorvetteConfig` fields `well_use_range`, `well_cone_deg`. With no well the side choice is identical to today.

**Tests** — extend `test_ram_corvette.gd` (dual-mode): with a well beyond the player, the charge direction is within 30°
of player → well; **with no well, the same side as the control**; a second Ram does not take the ticket; the ARMOR shove
moves the player toward the well; the Ram's attack-in-budget rows and the **73.2 s cloud_descent deadline row** (0.40 s
margin) stay green (no well exists in level 1). **Allowance: +2.5 s.**

### 2.15 Gravity Field weapon: the Bomber's gravity bomb leaves a slow field (t17)

`EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`) `_detonate()`: a `GRAVITY_BOMB` also
spawns `assault/scenes/hazards/gravity_field/gravity_field.tscn` into `Hazards.container(tree)` (none → nothing) at the
detonation point: `HazardField`, `kind = &"gravity_field"`, `radius` 150, `movement_penalty` 0.4, `duration` 3.5,
`avoid_weight` 0.6, no pull, no damage, a translucent ring sprite (t5) that fades over the last 0.5 s. Strongest-only and
the 0.5 cap come from `Hazards.penalty_at()`. Enemies feel `0.4 · (1 − resistance)`; the player feels 0.4 on thrust,
ceiling, boost (Open Space) or move and dash speed (Assault) — §2.2 / §2.3 built the consumers.

**Tests** — extend `tests/integration/test_enemy_ordnance.gd` / `test_bomber.gd`: a gravity bomb's detonation leaves one
field at the blast point that frees at 3.5 s; mines and pursuit bombs leave none; **two overlapping fields slow by 0.4,
not 0.64**; the player and a resistance-0.4 enemy are slowed by 0.4 and 0.24; no container → no field and the existing
ordnance rows unchanged. **Allowance: +1.5 s.**

### 2.16 Open Space hub: one tactical space (t18)

`open_space/scenes/levels/sector_hub.tscn` gains a `TacticalSpace` node (scene children, not rng draws, so every patrol
seed is unchanged) laid out as IDEAS §18.6's sketch: one gravity well at the centre, an energy anomaly 650–750 px from
it, and the three placed structures forming a cover line 450–550 px from the well on the side facing the hub, plus
2–3 `debris_drift` pieces (with `lifetime` 0). Candidate centre: bearing 22.5° on a 3200 px ring (between the gatling at
0° / 1500 px and the bomber at 45° / 1700 px). The `HazardContainer` from t11 stays. Clearance rule, computed by a sweep
on the real scene, never hand-picked: for every patrol group, `distance(anchor, hazard centre) − hazard radius − worst
idle offset − perceive_radius > 100 px` for every element of the space; for every `MissionTrigger`, `PickupBase` and the
player spawn, `distance − hazard radius > 300 px`.

**Tests** — extend `tests/integration/test_sector_hub_patrol.gd`: the clearance sweep above for every element; the
patrol seeds and positions are unchanged (existing rows); the space has at least one LOS blocker, so a real Sniper near
it can be refused a line. **Allowance: +1 s.**

### 2.17 Art (t5 hazard fields, t9 wrecks and structures)

Every image under `pixel-art-generation`: strict top-down orthographic (`view: "high top-down"`, `isometric: false`),
transparent background, saved with `./scripts/pixellab.sh`, opened and checked, then `--import`. Faction palette:
navy/black hulls, red/crimson accents, cool edge highlight (IDEAS §21); state colours: orange = armed / charging,
dark / off = destroyed.

**t5 — hazard fields** (`assault/assets/sprites/hazards/`): gravity well (accretion swirl, dark core with a bright
inner ring, ~192 px, 4–8 animation frames), energy anomaly (violet / magenta rings, distinct from the well, ~160 px,
4–8 frames, a dim and a lit state), gravity field ring (translucent, ~128 px, may be one frame scaled), reactor field
(orange-red unstable glow, ~96 px). The well and field's full `radius` is drawn in code as a faint ring (`_draw()`), so
the sprites stay small.

**t9 — wrecks and structures** (`assault/assets/sprites/wrecks/`): faction wrecks small (~40 px), medium (~72 px), large
(~110 px) — broken silhouettes, all lights off, scorch marks, not readable as live ships; an explosive-wreck overlay (an
exposed orange ordnance glow, 2 frames for the fuse blink); placed structures: damaged satellite (~96 px), abandoned
cargo platform (~128 px), broken station module (~128 px). Drifting debris reuses `debris_1..6.png`.

Tests: `test_entity_sprite_transparency.gd` (the scenes are under `assault/scenes/hazards/`, which it sweeps). Art tasks
produce imported PNGs (and `SpriteFrames` where animated) and a contact sheet note in their report; the scenes that use
them are t6, t7, t10, t12, t17. **Allowance: 0 s.**

### 2.18 Docs and phase close (t19)

Invoke `updating-project-docs`: `docs/architecture/modules/global.md` gains `global/hazards/`; `assault.md` the hazard
scenes and the wreck family; `open_space.md` the tactical space; `PROJECT.md` conventions gain "hazards are sampled by
the body; the mover owns enemy drift; runtime hazards live in the `HazardContainer`"; `CLAUDE.md` names the new gates
(`test_hazards.gd`, `test_context_avoidance.gd`, `test_player_hazards.gd`, `test_wreck.gd`, `test_wreck_spawning.gd`,
`test_hazard_projectiles.gd`) and the round-stops-on-wreck rule beside the projectile-ownership convention;
`docs/enemy-roster.md` the hazard profile and wreck columns; each hazard has its `HAZARD.md`; `tests/README.md` the
gate-time row for this phase. Then close the phase: `docs/epics-done/cmug23om70001m52wqfwclf3l/` (`PRD.md`,
`SOURCES.md`, `REPORT.md`) and a `## Phase 6 - as built (<date>)` section in the idea's `DECISIONS.md` listing every
deviation and the gaps left. **Allowance: 0 s.**

## 3. Build sequence

| Key | Step | Depends on | Allowance |
|---|---|---|---|
| t1 | Registry, `HazardInfo`, `HazardField`, `HazardDrift` (§2.1) | — | 0.5 s |
| t2 | Enemy drift and slow in `EnemyMover`, profile fields (§2.2) | t1 | 1.5 s |
| t3 | Player ships feel pull and slow (§2.3) | t1 | 1 s |
| t4 | Context-steering avoidance stage (§2.4) | t1, t2 | 3 s |
| t5 | Art: hazard fields (§2.17) | — | 0 |
| t6 | Gravity Well (§2.5) | t2, t3, t5 | 2 s |
| t7 | Energy Anomaly (§2.6) | t2, t3, t5 | 1.5 s |
| t8 | Rockets, bombs and missiles bend in fields (§2.7) | t1 | 1 s |
| t9 | Art: wrecks and structures (§2.17) | — | 0 |
| t10 | Wreck family (§2.8) | t1, t9 | 3 s |
| t11 | Wrecks from deaths, `HazardContainer` in level 1 and hub (§2.9) | t2, t10 | 2 s |
| t12 | Explosive wrecks and reactor fields (§2.10) | t11 | 2 s |
| t13 | `can_see_player()` and Sniper cover (§2.11) | t10 | 2.5 s |
| t14 | Fighter cover before a pass (§2.12) | t10, t13 | 2.5 s |
| t15 | Debris Charge (§2.13) | t10 | 1.5 s |
| t16 | Ram drives the player toward a well (§2.14) | t4, t6 | 2.5 s |
| t17 | Gravity Field from gravity bombs (§2.15) | t2, t3, t5 | 1.5 s |
| t18 | Hub tactical space (§2.16) | t6, t7, t11 | 1 s |
| t19 | Docs and phase close (§2.18) | all | 0 |

Total allowance ≈ 29.5 s against ≈ 40 s of headroom (≈ 200 s of 240 s at the end of Ph5). If a task finds GUT above
230 s before it starts, it applies the README's rules to recover time before adding rows, and says so in its report.

## 4. Test plan

The per-task rows live in each §2 section, with their boundary cases. Cross-cutting:
- **Gates that must stay green unchanged:** `test_enemy_mover_single_writer.gd` (no hazard writes enemy motion),
  `test_config_instance_isolation.gd` (new config fields are flat), `test_collision_layer_names.gd` (no new bit; every
  bit used is already named), `test_enemy_hurtbox_geometry.gd` / `test_contact_hitbox_geometry.gd` (wreck scenes follow
  the cover / shared-shape rules even though they are not enemies), `test_entity_sprite_transparency.gd`,
  `test_resource_uid_integrity.gd`, `test_project_load_integrity.gd`, every Ph2–Ph5 behaviour spec, every level-1 pin,
  density, deadline and attack-in-budget row.
- **Why the level-1 gates do not move:** they build their own containers without a `HazardContainer`, so no wreck, field
  or fragment spawns; and no well or anomaly is placed in level 1. The live level gets wrecks and fields, which never
  enter the enemy container.
- **Registry hygiene:** hazard tests use `add_child_autofree`; `scripts/check-test-leaks.sh` clean after t1, t10, t11.
- **Both harnesses** (R6.19): pull on enemies (t2, t6), pull on the player (t3, t6), avoidance per profile (t4), wreck
  spawning (t11), LOS blocking (t10, t13), anomaly (t7), Gravity Field (t17).

## 5. Risks

| Risk | Mitigation |
|---|---|
| The mover stage changes every enemy's motion | Pass-through rows bit-identical with no hazard and with a far hazard (t2, t4); early-out on `count() == 0` |
| Context steering snaps or sticks (Godot forum report, F1/F2) | 16 slots, interpolation, distance-scaled danger, previous-direction blend, min speed ratio; "target behind a well" row |
| A well becomes a magnet (F7) | Short reach (420 px), softened 1/r core, capture designed per ship (§2.2 table) |
| Gate time | Allowances sum to 29.5 s; before / after on every task |
| Wrecks crowd Assault | Cap 4, drift off in ~20 s, owner question 5 |
| Wreck physically pins the Assault player at the clamp | Wrecks move by position writes like small asteroids (no recorded squeeze bug); t10 row: a wreck pushed onto the player at the edge does not hold them for more than 2 frames, else the wreck yields |
| Enemy rounds stopping on wrecks changes balance | Only wrecks opt in (`stops_enemy_rounds()`); asteroids unchanged |
| Ram cover logic touches the thin 0.40 s deadline row | No well in level 1; the side choice is identical without a well; t16 re-runs the row |
| Static registry leaks between tests | Freed nodes always unregister in `_exit_tree`; `count()` row; autofree convention |
| Feel is untested by a human | Stated in the dossier; every value is a starting value |

## 6. Out of scope

Mines and minefields (Ph7); laser emitters, barriers and walls (Ph8); jammers, EMP zones and any consumer of
`disables_abilities` (Ph9); capital-ship and boss wrecks, modules remaining as wreckage (Ph19); carrier escort and hacker
positioning tactics (Ph10/18, Ph9); hazards acting on rail-driven spawns (Ph15), the Gunship (Ph10) and the station
(immovable; Ph11/19); placed wells or anomalies in Assault levels (Ph15); a designed gravity slingshot (nothing asks for
one); the anomaly's shield or targeting variants and the Ram's deliberate plate throw (owner questions 2 and 3 — each is
one task on top of this phase if wanted); hazard audio (Ph17); encounter composition around hazards (Ph13/14);
difficulty scaling of hazard values (Ph16).

## 7. Requirements coverage

| Req | Requirement (short) | Delivered by |
|---|---|---|
| R6.1 | `HazardInfo` with the seven fields | t1 |
| R6.2 | Same contract fits later hazards | t1 (duck-typed fixture row) |
| R6.3 | Hazards affect enemies by the same physics, unless resisted | t2, t3, t6 |
| R6.4 | Structure categories (wrecks, debris, satellites, cargo, station modules; wells, anomalies, reactor fields) | t9, t10, t12, t6, t7; EMP zones → Ph9; laser barriers → Ph8 |
| R6.5 | Placement forms tactical spaces | t18 |
| R6.6 | Enemies perceive through the same system; accidental hits; pushing the player | t1, t4, t10 (contact), t16 |
| R6.7 | Soft avoidance layer; context-steering decision | t4 (context steering chosen) |
| R6.8 | Strength per hazard and profile; committed rammer ignores | t2 (profile fields), t4 |
| R6.9 | Hazards as tools: sniper, fighter, ram, drone skim | t13, t14, t16, t4 (skim); carrier / hacker → Ph10/18, Ph9 |
| R6.10 | Well: radial pull growing to the centre; ships and projectiles | t1, t2, t3, t6, t8 |
| R6.11 | Avoid, skim, resist, dragged, hull stress, bait | t2, t4, t6 |
| R6.12 | Energy Anomaly, readable | t7 (swirl variant; shields / targeting → owner option, out) |
| R6.13 | Wrecks: cover, collision, drifting debris, explosive; capital wreck | t10, t11, t12; capital → Ph19 |
| R6.14 | Wreck as sniper hiding spot and fighter cover | t13, t14 |
| R6.15 | Gravity Field weapon | t17 |
| R6.16 | Debris Charge | t15 (passive; active throw → owner option, out) |
| R6.17 | `can_see_player()`; terrain occlusion | t10, t13, t18 |
| R6.18 | Strict top-down art per hazard | t5, t9 |
| R6.19 | Deterministic tests in both harnesses | every task's rows; §4 |
