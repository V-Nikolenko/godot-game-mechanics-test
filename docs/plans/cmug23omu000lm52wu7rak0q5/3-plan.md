# Enemy rework, phase 7: mines, minefields and the Mine Layer

Revision 3. Revision 2 answered plan review round 1 (§1.2). This revision answers round 2 (`4-review.md`) and the owner's "changes requested", which carried no comments of its own; the answers are listed in §1.3.

## Summary for the owner

- **For the player:** a new enemy, the Mine Layer, flies sideways across the fight and leaves a curved or zig-zag line of six mines in your path. It lays one line, breaks away, and comes back about 10–14 seconds later to lay the next one somewhere else, so danger builds up gradually. In Open Space its mines stay where they were laid: fly away, come back, and the minefield is still there. In Assault it crosses the screen once ahead of you and leaves.
- **Six kinds of mine**, each with its own shape and light. **Proximity** explodes when you get close. **Drifting** moves slowly. **Slow homing** creeps toward you once it notices you, and you can outrun it. **Chain** sets off nearby mines, so shooting one clears the whole linked group. **Pulse** is a small blast that weakens your boost and dash for 2.5 s. **EMP** knocks your boost and dash out for 2 s.
- **The Bomber's existing mine becomes the proximity mine** of this family. It behaves as before and gets the new art.
- **Enemies treat mines as hazards** and steer round them, using the hazard sense from phase 6. This was measured, not assumed. Careful ships (most of the roster) keep about 150 px from a mine. The Bomber and the Missile Corvette skim closer. The clumsy Ram Corvette sometimes clips a placed minefield, which makes it a lure.
- **Minefields as places:** a minefield can be placed in a level as a visible structure with a warning beacon. The hub gets one beside the phase-6 battleground. A placed minefield is dangerous to everyone, so you can lure enemies into it.
- **Where it appears:** one Mine Layer in the hub's ambient patrol, and one each in level 1's Deep Space and Planet Approach sections. Neither section waits for its enemies to be cleared.
- **Built:** the mine family, a boost-weakening hook on both player ships, a placeholder EMP hook for phase 9 to finish, the minefield structure, the Mine Layer (AI, art, hub and level placement), and tests in both modes.
- **Left out:** EMP effects on enemies and the real EMP effect on the player (phase 9). Placed minefields in Assault levels (phase 15; the scene already works there). Mine counts by difficulty (phase 16). Sound (phase 17). The race track's mine stays as it is.
- **A weakened boost never makes you slower than normal flight:** the Shift boost, the Boost Drive and the dash lose only the part of their speed that is above your normal speed.
- **Main risks:** (1) The tests are near their 240 s limit (216 s now). The first task must win back 12 s, and every task has a time allowance. (2) Bomber mines become hazards other enemies steer round, which could shift a level-1 timing test. Two fallbacks are already approved. (3) None of this has been play-tested: whether the mine lines can be dodged by feel is a judgement call.
- **Choices for you (default in brackets):**
  1. Should a *placed* minefield also hurt and be set off by enemies, while mines an enemy lays hurt only you? [Yes]
  2. Until phase 9 builds the real EMP, should the EMP mine's effect be "boost and dash unavailable for 2 s"? [Yes]
  3. Should the Mine Layer replace its oldest mine once it has 18 alive in Open Space (8 in Assault), rather than stop laying? [Replace the oldest]
  4. Should shooting a chain mine set it off (and its linked neighbours) rather than defuse it like the other mines? [Set it off]
  5. Should the pulse and EMP mines also weaken the Warp module's blink, not only the dash and boosts? [Yes]

## For every task

Phase 7 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`) stand unless a line below changes them.
- **Mine family = `EnemyMine extends EnemyOrdnance`**, `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`, `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }`
  (append-only). Scenes are `mines/<variant>_mine.tscn`, except PROXIMITY, which **is** the existing `enemy_ordnance/mine.tscn`: it keeps its path (it has no UID),
  its script becomes `EnemyMine` (`kind = 1`, `variant = PROXIMITY`) and its authored `warning_time` becomes 0.25 (every dropper already sets 0.25).
  `EnemyMineScenes` (`mines/enemy_mine_scenes.gd`) has `scene_for(variant)`, `pool_size_for(variant, cfg)` and `export_of(variant, property, fallback)`. The `EnemyOrdnance` contract is unchanged:
  `signal expired` once per life, `reset()`, `launch(dir, speed, target_point)`. A pooled mine never frees itself. A mine is never in group `enemies` and never scored.
- **Variant numbers live in the mine scenes** (trigger, warning, blast, effect). **The Mine Layer's `drop_mine` overrides only `arm_delay`, `eject_time` and the life
  (`mine_life` plus the lifetime backstop).** The Bomber's `drop()` keeps its Ph4 overrides, for PROXIMITY only.
- **Hostility:** `enum Hostility { PLAYER, ALL }`. PLAYER (default; every mine an enemy lays) is set off only by layer-128 hurtboxes and blasts through
  `ContactBlast` (Ph4). ALL (placed mines only) is also set off by a layer-512 area whose `get_parent()` is in group `enemies`, and blasts through
  `Hazards.pulse_damage(tree, at, blast_radius, blast_damage)`, the Ph6 rule that environmental blasts hurt both sides.
- **A mine is a hazard:** `hazard_info()` returns one `HazardInfo` updated in place: `kind = &"mine"`, **`radius = trigger_radius + hazard_pad`** (export `hazard_pad` 60),
  **`avoid_weight` 1.0** for every mine, `velocity` for moving mines, `source = self`, and no pull, slow or LOS block. These numbers were measured (plan §2.3).
  **Pooled hazards register on `launch()`** and unregister in `_mark_done()` and `_exit_tree()`. A mine never writes a ship's velocity, position or rotation.
- **Placed mines:** `placed = true` (an export) makes a mine self-owned (`expired -> queue_free`, backstop `max_time` 0, `mine_life` 0 unless authored). The setup
  runs in a **deferred** `_start_if_placed()` queued by `_ready()`, after every `_ready()` of the same add, so a parent `Minefield` has already set `placed`/`hostility`.
  A lone mine dropped in a scene arms, registers and triggers. Hostility-dependent setup (the `ProximityArea` mask) is applied in `launch()`.
- **`mine_life` 0 means "never fizzles"**; the `ProjectileLifetime` `max_time` is the backstop (0 = inert). `retire()` = fizzle (fade, no blast, `expired`).
- **Warning rule:** for every mine scene, `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`. `effect_radius` is `blast_radius` when
  `blast_damage > 0`, else `emp_radius`. `own_speed` is `home_speed` (HOMING) or `drift_speed` (DRIFTING), else 0. It is read from scene exports, never typed numbers.
- **Chain:** a CHAIN detonation calls `chain_trigger(chain_delay)` on every live mine whose centre is within `chain_radius` (via `Hazards.around()`, kind `&"mine"`,
  then filtered by centre distance). A chained mine skips its warning. Only CHAIN mines propagate.
- **Player hooks (on `PlayerBase`, implemented by both ships):** `apply_boost_disruption(strength: float, seconds: float)`, `boost_efficiency() -> float`,
  `signal boost_disruption_changed(efficiency: float)`, `MIN_BOOST_EFFICIENCY := 0.15`, `cruise_speed() -> float`. The strongest strength wins and the longest time wins;
  they never stack. **A disrupted speed scales only its excess over a floor:** `floor + (speed − floor) × efficiency` (Shift boost and Boost Drive: `cruise_speed()`;
  dash: `DashState.move_speed`), so a disruption never slows the ship below normal flight.
  **Efficiency is checked before anything is spent:** a refused boost spends no tank and no charge. `apply_emp(seconds: float, source: Node)`, `is_emp_disrupted()`,
  `signal emp_changed(active: bool)`. Ph7's stand-in effect is `apply_boost_disruption(1.0, seconds)`. **`EmpPulse.emit(tree, at, radius, seconds, source) -> int`**
  (`global/components/emp_pulse.gd`, static) is the one EMP entry point, the "same hook" Ph9's EMP Pulse uses. In Ph7 it reaches only group `player`.
- **Mine Layer** lives in `assault/scenes/enemies/mine_layer/`: `MineLayer extends BaseEnemy`, `MineLayerBrain extends EnemyBrain`, flat `MineLayerConfig` (`.tres` wins).
  `MineLayerBrain.Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only). `MineLayer.drop_mine(variant, rest_point) -> EnemyMine`
  is the only place a layer configures a mine. Pools are root `BulletPool` children with `persist_after_owner_death = true`. `WaveBuilder.MINE_LAYER` + `mine_layer()`.
  `ContactProfile` mode COLLISION. `hazard_avoidance` 0.8, `hazard_margin` 24. It joins group `enemies` in its own `_ready()` (`BaseEnemy` does not).
- **Minefield** lives in `assault/scenes/hazards/minefield/` (`Minefield extends Node2D`, `HAZARD.md`). Placed mines are unpooled, `hostility = ALL`, `placed = true`.
  It works in both modes. In Assault the field drifts down at 60 px/s, as wrecks do.
- **Where things live:** mines a layer or Bomber drops live in the enemy container (the pool's container, Ph4). Placed fields are scene children. The layer's wake trail
  lives in the layer's parent container. No Mine Layer, Bomber, or anything dropping persistent mines goes in an `ENEMIES_CLEARED` section.
- **Conventions kept:** brains tick on physics through the mover (single writer) and gate "stopped" checks on `own_velocity()`. Clocks are accumulated delta, with no `Timer`
  and no `create_timer`. Randomness comes only from `brain.rng` (the field's own seeded rng for `Minefield`). `accepts_tow()` is false in LAY. Facing follows
  `sprite_forward_angle` (layer art nose-down, the default `PI/2`). `TargetInfo` exposes `.position` / `.velocity`. Signals are declared with their arity. Per-frame prints
  sit behind `OS.is_stdout_verbose()`. Art comes only from PixelLab under the `pixel-art-generation` skill and is saved through `scripts/pixellab.sh`. Never hand-type a
  `uid://`. Every task appends its "built in tN" notes, and any deviation, to the Phase 7 section of `DECISIONS.md`.
- **Fixture enemy:** `tests/helpers/fixture_enemy.tscn`'s `HurtBox` has no shape and the fixture joins no group. A row that needs a mine to see it adds a 14 px
  `CircleShape2D` to that `HurtBox` and calls `add_to_group("enemies")` at runtime, before `add_child`. The shared fixture scene is not edited.
- **Tests:** GUT, written first. Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`); parameterise on a label string. Rows that await real
  physics run on the **8× clock** (`_scale_clock()` / `_restore_clock()` from `test_level1_drone_exit.gd`). A scenario several rows share is computed once. Run
  `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget.** Measure GUT with `scripts/gate-time.sh` before and after the task, and report both in the task report and in `tests/README.md` → Gate time.
  Allotments are in plan §2.17. GUT must stay ≤ 240 s. An over-allotment is fixed by sharing work, never by cutting an assertion.
- **Pass-through stays bit-identical:** with no hazard in reach, enemy velocity and rotation equal Ph6's. The Ph6 pass-through rows stay green.
- Numbers marked *starting value* in plan §2.18 are judgement, not research. Keep them unless a test row forces a change, and record any change in `DECISIONS.md`.
- Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

## 1. Problem

Today the Bomber can lay a short-lived line of one kind of proximity mine. Nothing else in the game denies an area over time, and nothing makes the player
remember where danger is. The idea (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.3, §6.9, §11.4, §18.6, §21–23, §40) asks for:

- a shared mine family with distinct behaviours;
- a Mine Layer that builds unsafe regions gradually (in Open Space they persist, so a place the player returns to is still dangerous);
- minefields placed as visible structures;
- enemies that avoid mines through the phase-6 hazard sense;
- readable art;
- tests in both modes.

### 1.1 Scope check (re-validated against the code on `agent/auto-dev` @ `e4ac6d1`)

The research stage of this epic left no `1-context.md` / `2-research.md`. This plan re-read the code and the decision log itself. It makes no genre claims: every number
is an earlier phase's, a measurement (§2.3), or a starting value marked as judgement (§2.18). Findings that change the phase's scope:

| # | Finding | Effect on scope |
|---|---|---|
| S1 | `EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`) already has `Kind.MINE`: an eject that stops on a rest point, a polled proximity trigger, a warning, a `ContactBlast`, a shot that defuses it, `mine_life` with a fizzle and a `ProjectileLifetime` backstop. Ph4 said "Ph7's Mine Layer and mine variants should extend this family". | The proximity variant is the existing mine. Phase 7 adds five variants on the same contract and moves mine-only logic into a subclass. |
| S2 | `BulletPool.persist_after_owner_death` exists (Ph4). `Bomber.drop()` (`bomber.gd:69-97`) is the single configuring call. | The Mine Layer copies the Bomber's pool shape. No new lifetime rule. |
| S3 | The epic says mines "use phase 5's explosion radius". Ph5's rockets blast through `ContactBlast` with a `blast_radius`. Ph6 added `Hazards.pulse_damage` for blasts that hurt both sides. | PLAYER mines use `ContactBlast`, ALL (placed) mines use `pulse_damage`. The warning rule uses the Bomber's 440 px/s mine band. |
| S4 | Mines are not hazards today. `HazardInfo` names `&"mine"` as a planned kind ("Ph7 mines join the same registry with no change to the AI"). | Registration only, no AI change. But the footprint must be chosen from a measurement: at `radius = trigger_radius` ships pass inside the trigger (§2.3). |
| S5 | §11.4 Gravity Field was moved to Ph6 and is built (`assault/scenes/hazards/gravity_field/`). | Not in this phase. |
| S6 | The §16 "Explosive collision" profile (assigned to Ph7 by Ph1's coverage table) is built: `ContactProfile.Mode.EXPLOSIVE` (Ph2). | Nothing to build. |
| S7 | No player-side hook for boost efficiency or EMP exists. The Open Space boost is `OpenSpacePlayerShip._step_boost()` plus the Boost Drive (`engine_boost_module.gd`). Assault has `DashState` (a 350 px/s roll) and the Warp module's blink (`dash_state.gd:47-50`). `EMPBlastModule` is the *player's* EMP. | Build a `PlayerBase` disruption hook used by both ships, and the `EmpPulse` entry point with a stand-in player effect. EMP on enemies is Ph9. |
| S8 | Ph4 deferred reconciling the race-mode mine (`assault/scenes/race/track/mine.gd`) to Ph7. Racers are excluded from the rework. | Not merged. The race mine stays a race prop. |
| S9 | Ph6 leaves GUT at **216.3 s** of the 240 s ceiling: "Ph7 must start by recovering gate time". | First task: recover ≥ 12 s. Every task gets an allotment (§2.17). |
| S10 | Ph6 placed hazards only in the hub and deferred placed Assault hazards to Ph15. | Minefields are placed in the hub. The scene is proven in the Assault harness but not placed in a level. |
| S11 | Level-1 specialists are pinned and counted against frozen constants with a 2.5× gate (`test_level1_specialist_spawns.gd`). Deep Space peaks at **7** of 12.5 (at 15.50 s). Planet Approach peaks at 7 of 7.5 (at 98.0 s). A spill-over row keeps persistent ordnance out of the next `ENEMIES_CLEARED` section. | The Mine Layer counts as a specialist. The 16.0 s Deep Space layer lands on that section's peak (8 ≤ 12.5). The Planet Approach layer goes at 47.0 s, far from its 98 s peak (5–6 + 1 ≤ 7.5). |

### 1.2 Revision 2: answers to plan review round 1

| Finding | Answer | Where |
|---|---|---|
| B1 avoidance cannot keep ships outside the trigger | Measured with `Steering.context_avoid` (table in §2.3). The footprint becomes `trigger_radius + hazard_pad` 60 at weight 1.0 for every mine, and the Mine Layer's own `hazard_avoidance` becomes 0.8. Rows now assert measured bounds per avoidance level plus a `registers_hazard = false` control. The promise to the owner is restated by avoidance level. | §2.3, §2.10, §2.12 |
| B2 zig-zag rows contradict each other | Mines sit on the vertices: half-wavelength 100 px, amplitude ±35 px, so the chord is 122.1 px at 35.0°. ARC depth becomes 110, giving at most 35.1°. The rows are rewritten from that geometry. | §2.12 |
| B3 numbers fail the warning rule | `home_speed` becomes 60 (512 ≥ 500). `mine.tscn`'s authored `warning_time` becomes 0.25, the value every dropper already applies. The Mine Layer no longer overrides warning or blast. | §2.2, §2.4, §2.11 |
| B4 a refused Boost Drive burns a tank | The efficiency check sits in `_step_boost` before `try_spend_tank()`, and also in the default boost's start condition. `try_activate` keeps a guard for the Assault H path. A "no tank spent" row is added. The Warp blink obeys the disruption (owner question 5). | §2.6 |
| B5 hub anchor breaks the Ph6 clearance rule | The anchor moves to bearing −22.5° on the 2600 px ring, (2402, −995). The Mine Layer joins `_patrol_groups()` and `Minefield` joins `_element_radius()`. Computed worst clearance: 410 px (> 100). | §2.15 |
| M1 wrong gate-time files | t1 now names the measured 1× files. A production speed-up is a last resort. 12 s is a hard floor. | §2.17 |
| M2 dropper overwrites damage | `drop_mine` overrides only arm / eject / life. A row pins PULSE 8 and EMP 0 after a drop. | §2.11 |
| M3 unstated wall-rule departures | Aligned: `t_lead = t_approach_left + min(c, lead_horizon)` (only `c` capped), and the drop fires after the rest point is passed (the Bomber's "plus"). The pass-to-pass timing is restated, and the departures that remain are recorded. | §2.12 |
| M4 `test_wreck.gd` is a hand list | `mine_layer.tscn` is added to `_SHIP_SCENES` explicitly. | §2.11 |
| M5 parallel tasks collide | Mine-variant tasks are chained, the pulse task is split from the player hook, the beacon wiring belongs to the art task, and the layer tasks are chained. | §3 |
| M6 factual slips | Deep Space peak 7, `mine.tscn` has no UID, `TargetInfo.position`, the plate hierarchy. All corrected; the ALL filter now checks only `area.get_parent()`. | §1.1, §2.1 |
| M7 unsourced numbers, dead behaviours | §2.18 lists every number's origin. Hub drifting mines get a direction and a 120 px leash. The `placed` export makes a lone mine arm. | §2.4, §2.10, §2.18 |
| M8 pulse task too big | Split three ways: player hook (large), pulse mine (small) and EMP (medium). | §3 |

### 1.3 Revision 3: answers to plan review round 2 and the owner

The owner's "changes requested" carried no comments of its own, so this revision answers the round-2 findings. The five owner questions stay open, each with its default.

| Finding | Answer | Where |
|---|---|---|
| N1 LAY starts wherever APPROACH arrives, so the line comes out crooked | APPROACH now seeks a run-in point `R = S − u·run_in` (150 px, the reviewer's measured value), then follows R → S along the axis at `lay_speed`. LAY and its rows start at S. `t_approach_left` adds `run_in / lay_speed`. A perpendicular-arrival row is added. Measured by the reviewer with the run-in: ≤ 33° and ≤ 23 px. | §2.12 |
| N2 the shell needs mine scenes from later tasks | t10 depends on t6 (which already follows t3 and t4); t10 runs alongside t7–t9 only; t11 depends on t10 alone. | §3 |
| N3 a 40° step cannot give 380 px against a standing player; the "Gradual" row contradicts its fallback | Each try rotates C about P by `θ = 2·asin(min(1, (min_pass_separation + 10) / (2·|C − P|)))` (75.1° at 320 px), tries +θ, −θ, +2θ, −2θ. A `spread_fallbacks` seam counts plans that proceeded anyway; the spacing row is asserted only for the others. Two scenarios: a standing stub and a stub moving at 220 px/s. | §2.12 |
| N4 the fixture enemy's hurtbox has no shape | Rows that need a mine to see the fixture add a 14 px `CircleShape2D` at runtime (and the group). Stated in *For every task*, §2.1 and §2.10. | §2.1, §2.10 |
| N5 the minefield's clearance radius ignores the drift leash and reads a missing property | `_element_radius()` = `radius + (drift_leash if w_drifting > 0 else 0) + EnemyMineScenes.export_of(PROXIMITY, &"trigger_radius", 80.0)` = 400 for the hub field. Clearances recomputed: Mine Layer 586 px, Gatling 775 px (rule > 100). | §2.15 |
| N6 hand-placed mines are ready before their field | The placed setup moves to a deferred `_start_if_placed()`; the `ProximityArea` mask is set in `launch()`. Both read `placed`/`hostility` after the field's `_ready()` has set them. A boundary row authors a child with the wrong values. | §2.1, §2.10 |
| N7 the disrupted Boost Drive and dash drop below cruise | Every disrupted speed is `floor + (speed − floor) × efficiency`: Shift boost and Boost Drive floor at the new `PlayerBase.cruise_speed()` (Open Space `max_speed` 420, Assault `MoveState.move_speed` 360); the dash floors at `DashState.move_speed` 180. Rows rewritten with the new numbers. | §2.6 |
| N8 two ambiguous rows | The real-mover avoidance row is head-on (lateral 0). The layer's "keeps clear" row excludes the pass it is breaking off from and its tail-drop mines. | §2.3, §2.12 |
| N9 lose-radius claim, persistence row, exit probe | The claim is restated for a player at ≤ 220 px/s and asserted from the config (1421 < 1500). The persistence row teleports the stub beyond `lose_radius` of the layer. DISENGAGE with no planned pass exits along the current heading, so the probe measures the real exit. | §2.12, §2.14, §2.16 |
| N10 the levers covered only level-1 gates | They cover any existing row (`test_bomber.gd`, `test_enemy_ordnance.gd`, level 1) that fails because Bomber mines now register as hazards. | §2.1 |
| N11 the close-out task is small | t16 is medium. | §3 |
| (found while revising) a layer behind a fast player can never reach R | Open Space only: after `approach_max_seconds` 6.0 s in APPROACH without committing, the pass is re-planned once in the standing-player (fence) form from the layer's current bearing and frozen at once. A `fence_fallbacks` seam and a row pin it. | §2.12 |

## 2. Design

### 2.1 The mine family: `EnemyMine`

**File:** `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`, `class_name EnemyMine extends EnemyOrdnance`. One script carries every variant:
- `@export var variant: Variant`, with `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }` (append-only);
- `@export var hostility: Hostility`, with `enum Hostility { PLAYER, ALL }`, default PLAYER;
- `@export var hazard_pad: float = 60.0` and `@export var registers_hazard: bool = true` (§2.3);
- `@export var placed: bool = false` (below).

**Why a subclass, not more `EnemyOrdnance.Kind` values:** mine behaviour roughly triples (six variants, hazard registration, chain links, retire, placed mode). Bombs
share none of it. `EnemyOrdnance` keeps the bombs and the shared contract. It gains three small virtual hooks the subclass overrides, so the bomb code paths stay
byte-identical:
- `_move_mine(delta)`: today's MINE branch of `_move()`;
- `_trigger_seen() -> bool`: today's `_player_in_range()`;
- `_on_detonated()`: called inside `_detonate()` after `_mark_done()`, in place of the hard-coded `ContactBlast` + gravity field.

`_RESET_PROPS` is a `const` today, so `EnemyOrdnance` gains an overridable `_reset_props() -> Array` that returns it, and `EnemyMine` appends its own exports.

Alternative rejected: a component per variant (a `MineBehaviour` child node). Six nodes per pooled mine and a second contract buy nothing over an enum `match` in one script.

**What stays as it is (Ph4 contract):**
- `signal expired` fires once per life.
- `reset()` restores the authored exports.
- `launch(dir, speed, target_point)` starts a life; arming counts from launch.
- A player hit on the `HurtBox` (Health 1) defuses. CHAIN mines are the exception: shot = detonate (owner question 4; §2.5).
- The trigger is a **poll** of `ProximityArea.get_overlapping_areas()` once armed.

**New shared behaviour:**
- **`mine_life` 0 = never fizzles.** The MINE branch's fizzle guard becomes `mine_life > 0.0 and _clock >= mine_life`. The Bomber always sets 8.0, so it is unchanged.
- **`retire()`** starts the fizzle (`fizzle_time` fade, no blast, then `expired`). The Mine Layer's live cap uses it.
- **Hazard registration.** `hazard_info()` returns one `HazardInfo`: `kind = &"mine"`, `radius = trigger_radius + hazard_pad`, `avoid_weight` 1.0, `velocity` (zero unless
  the mine moves), `source = self`, no pull / slow / LOS block. `position` and `velocity` are refreshed on every `_physics_process`.
  - **Pooled mines register on `launch()`**, because a mine sitting idle in a `BulletPool` is in the tree (`PROCESS_MODE_DISABLED`, `bullet_pool.gd:66-71`), and
    registering in `_enter_tree()` would plant phantom hazards at the pool. This deviates from Ph6's register-in-`_enter_tree()` rule.
  - Unregister in `_mark_done()` and `_exit_tree()` (both idempotent; `Hazards.unregister` tolerates a missing node).
  - `registers_hazard = false` skips registration (the control in tests, and a pre-approved lever, below).
- **Placed mode (`placed = true`).** Every `EnemyMine._ready()` queues `_start_if_placed.call_deferred()`. Deferred calls run after every `_ready()` of the same add, so
  a parent `Minefield` (whose `_ready()` runs after its children's, Godot's child-first order) has already set `placed` and `hostility` on an editor-placed child.
  `_start_if_placed()` does nothing unless `placed` is true (so pooled mines are untouched). Otherwise the mine:
  - connects `expired -> queue_free`;
  - sets its `ProjectileLifetime.max_time` to 0 (inert);
  - sets `mine_life` to 0 unless the scene authored a nonzero value;
  - calls `launch(Vector2.ZERO, 0.0, global_position)`, so it arms after `arm_delay` and registers.

  This is how a standalone mine dropped into any scene works ("standalone mines" in the epic). `Minefield` sets `placed = true` on generated mines before `add_child`
  and on AUTHORED children in its own `_ready()`; both reach the same deferred path.
- **Hostility is applied in `launch()`**, never in `_ready()`: `launch()` sets the `ProximityArea` mask from the current `hostility` (128 for PLAYER, `128 | 512` for ALL).
  So a value set by a parent after the mine's `_ready()` still takes effect, and a pooled mine relaunched with a different hostility is correct.
- **Hostility ALL:**
  - The `ProximityArea` mask becomes `128 | 512` (set in `launch()`). `_trigger_seen()` accepts a layer-128 area, or a layer-512 area whose `get_parent()` is in group `enemies`.
    - That accepts a ship's hull `HurtBox`, which is a direct child of the `BaseEnemy` root.
    - It rejects other mines' hurtboxes (their parent is a mine), rocket shoot-down boxes (their parent is the rocket) and a Ram's plate hurtboxes (`Plates/PlateX/HurtBox`:
      the parent is an `ArmorPlate`, not in `enemies`). The Ram's hull hurtbox still sets it off.
  - The blast is `Hazards.pulse_damage(get_tree(), global_position, blast_radius, blast_damage)`. It uses centre distance, hits both sides and bypasses `EnemyShield`;
    a plated Ram deflects it (Ph6's rule).
  - PLAYER mines keep `ContactBlast.spawn(get_parent(), ...)`.
- **Look:** `_draw()` keeps only the state overlay (armed blink, warning blink, effect ring) on top of a `Sprite2D` child named `Sprite`. The `body_color` circle is
  drawn only when the scene has no `Sprite` texture, which is the case until the art task (§2.9).

**The Bomber after this task:** `mine.tscn`'s script becomes `enemy_mine.gd` (`kind = 1`, `variant = PROXIMITY`). Its authored `warning_time` changes 0.5 → 0.25. Behaviour
is unchanged, because `Bomber.drop()` always sets `warning_time = config.mine_warning` (0.25) and no test reads the authored 0.5. The change makes the scene itself pass the
warning rule (§2.2). `EnemyOrdnanceScenes.MINE` still points at it. Every `test_bomber.gd` / `test_enemy_ordnance.gd` row stays green unchanged.

**The one behaviour change:** Bomber mines are now hazards, so other enemies steer round them (§2.3), the Bomber included when it turns back across its own line. Pre-approved
levers, in order, if **any existing row** turns red *because of* the registration (a level-1 gate, or a `test_bomber.gd` / `test_enemy_ordnance.gd` row; check by re-running
the row with `registers_hazard = false`):
1. `hazard_pad = 0` on `mine.tscn`;
2. `registers_hazard = false` on `mine.tscn`.

The task reports which lever, if any, it used, and which row forced it. No gate bound moves and no assertion changes.

**`EnemyMineScenes`** (`mines/enemy_mine_scenes.gd`, RefCounted; the `EnemyRocketScenes` shape):
- `scene_for(variant) -> PackedScene`.
- `pool_size_for(variant, cfg) -> int`, duck-typed on `max_live_mines` and the flat weights `w_<variant>`:
  - PROXIMITY = `max_live_mines + 2`;
  - every other variant with weight > 0 = `ceil(max_live_mines × w / Σw) + 2`;
  - weight 0 = 0 (the pool is not built).
- `export_of(variant, property, fallback)` reads a root export through `PackedScene.get_state()`, so tests and gates read numbers from the scenes, never typed copies.

**Ownership:** pooled mines are owned by their pool until the owner dies, then handed over (`expired -> queue_free`). Placed mines are self-owned from the start. Both obey
"exactly one owner".

**Tests (`tests/integration/test_enemy_mines.gd`, new; the shared mine spec file used by §2.2–§2.8 too):**
- PROXIMITY is `mine.tscn`: `EnemyMineScenes.scene_for(PROXIMITY) == EnemyOrdnanceScenes.MINE`, its script is `EnemyMine`, and its authored `warning_time` is 0.25.
- Registration is launch-scoped:
  - a pooled, unlaunched mine is not counted by `Hazards.count()`;
  - after `launch()` it is, with `kind == &"mine"` and `radius == trigger_radius + hazard_pad`;
  - after detonate, defuse, fizzle or `retire()`, it is not;
  - a freed mine is not (the `_exit_tree()` row);
  - `registers_hazard = false` is never counted.
- Lifetime boundary: `mine_life = 0` → still live at 30 s (hand-ticked); `mine_life = 8` → fizzles at 8.0 s ± 1 tick (the Ph4 value, unchanged).
- Placed mode: a bare `placed = true` PROXIMITY mine added to a scene arms after `arm_delay`, is registered, is set off by the player stub (8× real physics) and frees
  itself after its blast (`is_instance_valid` false). A pooled mine never frees itself (control).
- Ready order (boundary): a parent node whose `_ready()` sets `placed = true` and `hostility = ALL` on a child mine authored with `placed = false` / PLAYER (the
  AUTHORED-field shape) → after one frame the child is self-owned, registered and its `ProximityArea` mask is `128 | 512`.
- Hostility:
  - `BaseEnemy` does not join group `enemies` (every shipped enemy's own `_ready()` does) and `tests/helpers/fixture_enemy.gd` does not either. Its `HurtBox`
    (`fixture_enemy.tscn`, layer 512) also has **no `CollisionShape2D`**, so no `get_overlapping_areas()` poll can see it. These rows therefore add a
    `CollisionShape2D` with a 14 px `CircleShape2D` to the fixture's `HurtBox` and call `add_to_group("enemies")`, both at runtime before `add_child`. The shared
    fixture scene is not edited.
  - A PLAYER mine is not set off by a `fixture_enemy` sitting inside the trigger radius (8×).
  - An ALL mine is set off by it, and its blast lowers that enemy's Health and the player stub's.
  - Boundary: an ALL mine is not set off by another mine, a rocket's shoot-down box, or a Ram plate's hurtbox alone (a plate positioned inside the radius with the hull outside).
- `retire()` gives no blast and exactly one `expired` (signal-count watcher).
- The avoidance rows of §2.3.
- `test_enemy_bullet_lifetime.gd`: one time-only row per variant scene, read from `EnemyMineScenes.export_of`. Its backstop `max_time` is ≥ its `mine_life`, or the
  backstop is inert only for placed use. Mine speeds never enter `_every_shipped_enemy_bullet_speed()`.
- Every Ph4 Bomber row green unchanged (named in the task report).

### 2.2 Trigger, warning and blast numbers

**Shared numbers.** Every new variant scene authors the Bomber's mine numbers unless its section says otherwise:
- `trigger_radius` 80;
- `arm_delay` 0.5;
- `warning_time` 0.25;
- `blast_radius` 48;
- `blast_damage` 30;
- `hazard_pad` 60.

The Mine Layer's `drop_mine` does not override trigger, warning or blast (§2.11). The scene is the only source.

**Rule, asserted from scene exports, never typed numbers:** `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`. The terms:
- `effect_radius` is `blast_radius` when `blast_damage > 0`, else `emp_radius`. For PULSE (blast 8) that is the stricter `blast_radius`, not `pulse_radius`.
- `own_speed` is `home_speed` (HOMING) or `drift_speed` (DRIFTING), else 0.

The rule means a player crossing at the top of the Ph4 mine band (440 px/s) is still inside the effect when it fires. The values it gives:

| Variant | (trigger + effect) / warning | Needs | Slack |
|---|---|---|---|
| PROXIMITY (`mine.tscn`, after 0.5 → 0.25) | 128 / 0.25 = 512 | 440 | 72 |
| DRIFTING (35 px/s) | 512 | 475 | 37 |
| HOMING (60 px/s) | 512 | 500 | 12 |
| CHAIN | 512 | 440 | 72 |
| PULSE (blast 48) | 512 | 440 | 72 |
| EMP (blast 0, `emp_radius` 190) | 270 / 0.25 = 1080 | 440 | 640 |

The Bomber's own config overrides (`bomber_config.gd`, `mine_warning` 0.25) already pass this rule in `test_bomber.gd`, and that row is unchanged.

**Tests (in `test_enemy_mines.gd`):**
- The inequality row for every variant scene (from `export_of`).
- Boundary rows:
  - a synthetic mine with `warning_time` 0.4 and blast 48 fails it;
  - a HOMING mine with `home_speed` 75 fails it (the round-1 number).
- Dual-mode real-physics rows (8×) for PROXIMITY:
  - a stub crossing at 220 px/s through the trigger radius takes the blast;
  - a stub that stops at `trigger_radius + 30` does not.

### 2.3 Mine hazard footprint and enemy avoidance (measured)

**The measurement.** `Steering.context_avoid()` (`global/enemy_ai/steering.gd:242`) was run headless against mines, integrated the way
`tests/unit/test_context_avoidance.gd::_fly()` does (60 Hz, `prev_dir` fed back, only hazards within the mover's reach). The ship flew start (−500, lateral) → (500, lateral),
with the mine at the origin and trigger 80. The table gives the **closest approach of the ship's centre to the mine's centre** (px), for lateral offsets 0 / 30 / 60.

| Footprint (`radius`, weight) | avoidance | margin 24, 200 px/s | margin 24, 300 px/s | margin 60, 200 px/s |
|---|---|---|---|---|
| 80, 0.5 (round-1 PLAYER) | 0.6 | 14 / 31 / 60 *(reviewer)* | — | — |
| 80, 1.0 | 0.6 | 61 / 69 / 76 | 69 / 73 / 81 | 68 / 75 / 81 |
| 140, 1.0 (**chosen**) | 0.5 | 66 / 80 / 87 | 73 / 82 / 89 | 73 / 84 / 88 |
| 140, 1.0 (**chosen**) | 0.6 | 90 / 99 / 109 | 96 / 105 / 113 | 93 / 106 / 113 |
| 140, 1.0 (**chosen**) | 0.8 | 152 / 152 / 156 | 155 / 159 / 158 | 170 / 170 / 171 |
| 140, 1.0 (**chosen**) | 1.0 | 178 / 176 / 179 | 181 / 179 / 183 | 215 / 214 / 216 |
| no hazard (control) | any | 0 / 30 / 60 | 0 / 30 / 60 | 0 / 30 / 60 |

**Fields (footprint 140, weight 1.0), ship at 240 px/s:**

| Case | avoidance 0.5 | 0.6 | 0.8 | 1.0 |
|---|---|---|---|---|
| 9-mine RING (field radius 200), crossed at lateral 0 / 100 / 200 / 300, margin 24 | 68 / 77 / 85 / 114 | 96 / 102 / 110 / 130 | 155 / 155 / 159 / 162 | 184 / 183 / 187 / 196 |
| 6-mine laid line (122 px chords, ±35 px), crossed square-on, margin 24 | 29–38 | 60–67 | 149–152 | 175–176 |

**Chosen:** `radius = trigger_radius + hazard_pad` (60) and `avoid_weight` 1.0 for **every** mine, PLAYER and ALL. A smaller pad or weight lets an avoidance-0.6 ship cut
inside the trigger even against a single mine.

**What that means in play (the promise, by avoidance level):**
- **≥ 0.8** (Fighter, Gatling, Sniper, Razor, Swarm, Support, and the Mine Layer itself after this phase): keeps ≥ 145 px from a mine's centre, so it never enters a trigger
  radius, even for a 40 px hull (80 + 40 = 120).
- **0.6–0.7** (Bomber, Missile Corvette): skirts a single mine at ≈ 90–110 px, and squeezes between the mines of a laid line at ≈ 60–67 px. It can graze a placed
  (ALL) field.
- **0.5** (Ram Corvette): often grazes. A placed field is a real lure for it.

PLAYER mines cannot be set off by enemies at all, so for them avoidance is readability only. Enemies do not fly through their own side's mines.

**A wall of mines is routed round, slowly.** Against the laid line with the target straight behind its end, a 0.6 ship slid along the line and round its far end in 14.8 s for a
1400 px trip (1.0: 16.6 s). That is Ph6's context stage working as designed (hysteresis keeps the side it chose). It is why Bomber-mine registration can move a level-1 timing
gate (levers in §2.1).

**Tests (in `test_enemy_mines.gd`, t2):**
- **Pure-stage rows**, fed through the registry:
  - Launch a real PROXIMITY mine at the origin, then integrate `Steering.context_avoid()` over `Hazards.around()` exactly as the table does (the `_fly()` shape copied into
    the test).
  - avoidance 0.6, margin 24, 200 px/s, offsets 0 / 30 / 60 → closest approach ≥ 85 px (measured 90 / 99 / 109), so it is > `trigger_radius`.
  - avoidance 0.8 → ≥ 145 px (measured 152 / 152 / 156).
  - The same runs with `registers_hazard = false` → closest approach equals the offset ± 1 px (the control).
- **One real-mover row** (8×), **head-on** (lateral offset 0; at lateral 60 the "+ 100" clause would fail, 156 < 160): a `fixture_enemy` with `hazard_avoidance` 0.8 and
  `hazard_margin` 24 seeks through a launched mine at 200 px/s → closest approach ≥ 120 px, and ≥ the same run's control (`registers_hazard = false`, ≈ 0 px) + 100 px.
- Rows for fields and for the Mine Layer are in §2.10 and §2.12; they use the numbers above.

### 2.4 Drifting and homing mines

**DRIFTING** (`mines/drifting_mine.tscn`; no Mine Layer weight by default, placed fields use it):
- After the eject, it moves at `drift_speed` 35 px/s along `drift_direction`. A launched mine takes its launch direction; a placed mine uses the export, and
  `Vector2.ZERO` means still.
- `drift_leash` 0 (default) → it fizzles once it has travelled `drift_max_distance` 1400 px (40 s, the wreck's 40 s life).
- `drift_leash` > 0 → it ping-pongs along its direction within `drift_leash` of its placed (local) position and never fizzles on distance. Placed fields use this, so a
  hub field's drifting mines move for ever without wandering off.
- It does **not** bend in fields (`hazard_pull_scale()` 0, as Ph6 decided for mines), so its distance cap holds.
- `HazardInfo.velocity` is its velocity, so the avoidance stage leads it.
- Position writes are local (`position`), so a field that moves carries its mines.

**HOMING** ("slow homing", `mines/homing_mine.tscn`):
- Once armed, it notices the player when the player's centre is within `notice_radius` 260 px.
- It then creeps toward `TargetInfo.player(tree).position` at `home_speed` **60** px/s, turning at `home_turn_rate` 2.0 rad/s (`Steering.turn_toward`).
- It stops creeping when the player is beyond `home_lose_radius` 380 px, or when it is `home_max_distance` 900 px from its launch point (it then holds there).
- No player → no motion.
- A sensor `Eye` sprite child faces the player while noticing.
- Any player faster than 60 px/s outruns it. That is the counterplay, and a test pins it.

**Tests (dual-mode, hand-ticked through `EnemyMine._physics_process`, which is position-only and needs no physics):**
- DRIFTING:
  - moves `35 × t` ± 1 px along its direction;
  - fizzles at 1400 px;
  - placed with a zero direction is still;
  - placed with `drift_leash` 120 never ends more than 120 + 1 px from its placed point over 60 s, and is still live.
- HOMING:
  - does not move before it is armed;
  - does not move with the player at 270 px (boundary just outside `notice_radius`), and moves toward the player at 250 px;
  - loses a player who retreats at 120 px/s once the gap passes 380;
  - never ends more than 900 px from its launch point;
  - heads toward the live player each tick within the turn cap;
  - in Assault never leaves `projectile_world_rect` (it holds at its own cap first).
- The warning row covers both variants with their own speed added (§2.2).

### 2.5 Chain mine and chain propagation

**CHAIN** (`mines/chain_mine.tscn`): `chain_radius` 150, `chain_delay` 0.2 s, `shot_detonates` true (shot = detonate, not defuse; owner question 4).

**Propagation:** when any CHAIN mine detonates (by trigger, shot or chain), it calls `chain_trigger(chain_delay)` on every *other* live `EnemyMine` whose centre is within
`chain_radius`. The mines are found through `Hazards.around(global_position, chain_radius)`, filtered to `kind == &"mine"` and `source is EnemyMine`, then by centre distance.
That last filter is needed because `around()` includes each info's footprint radius (140).

**`chain_trigger(delay)`:** ignored if the mine is done or already chained. Otherwise `_chained = true`, and the mine detonates once its own accumulated clock has advanced
`delay`. There is no warning, armed or not: a chain is physical.
- A chained non-CHAIN mine runs its own `_on_detonated()` (blast, pulse or EMP) but propagates no further.
- A chained CHAIN mine propagates. The result is a visible ripple at 0.2 s a hop.

**Readability:** every CHAIN mine draws a faint dotted "fuse link" (orange, alpha 0.35, width 1) to each mine within `chain_radius`. The set is recomputed every 0.5 s on
its own clock, not every frame, so a player can see which mines are linked before shooting one. `link_points()` exposes it.

**Tests (dual-mode, hand-ticked; the chain is registry-driven, so no physics is needed):**
- Four CHAIN mines 120 px apart in a line, the first set off → detonations at 0, 0.2, 0.4, 0.6 s ± 1 tick.
- A PROXIMITY mine 120 px past the last CHAIN mine detonates at 0.8 s. A PROXIMITY mine 120 px beyond that one does not (a non-CHAIN mine stops the chain; boundary).
- A CHAIN mine 151 px away is not reached (the `chain_radius` boundary); one at 149 px is.
- Shooting a CHAIN mine with a player bullet (8× real physics) detonates it and its neighbours. Shooting a PROXIMITY mine defuses it (no blast; the Ph4 row is unchanged).
- A mine already done is never re-triggered (each mine emits `expired` exactly once).
- Mixed hostility: a PLAYER CHAIN mine that sets off an ALL mine produces the ALL mine's `pulse_damage` (enemies hurt).
- `link_points()` lists exactly the neighbours within `chain_radius`.

### 2.6 Boost disruption: the player hook on both ships

**On `PlayerBase`** (`global/entities/player_base.gd`):
- `apply_boost_disruption(strength: float, seconds: float) -> void`. `strength` is 0..1. The live strength becomes `max(live, new)` and the remaining time `max(live, new)`,
  so they never stack.
- `boost_efficiency() -> float` = `1 − strength` while active, else 1.0.
- `signal boost_disruption_changed(efficiency: float)`, emitted on start, on change and at the end.
- `MIN_BOOST_EFFICIENCY := 0.15`.
- `cruise_speed() -> float`, virtual, the speed of normal flight a disrupted speed never drops below. `OpenSpacePlayerShip` returns `max_speed` (420). The Assault fighter
  returns `MovementStateMachine/MoveState`'s `move_speed` (360, not overridden in `player_fighter.tscn`; `assault/scenes/player/states/move_state.gd`). The base returns 0.
- **The excess rule:** a disrupted speed is `disrupted(speed, floor) = floor + (speed − floor) × boost_efficiency()`, so only the part above normal flight shrinks.
- `_step_disruption(delta)`: accumulated delta, no `Timer`. It is called from `OpenSpacePlayerShip._physics_process` and the Assault fighter's `_physics_process`, a
  hand-steppable seam like `BoostMeter.step()`.

**What efficiency changes.** It is read where it is used and never cached, and no export is ever written.

**Open Space Shift boost** (`player_ship.gd::_step_boost`, lines 380–464). Every refusal happens **before anything is spent**, keeping the "check before spend" contract
the comments there state:
1. **Boost Drive branch:** the condition becomes
   `boost_pressed and boost_efficiency() >= MIN_BOOST_EFFICIENCY and drive.can_activate() and (_boost_meter == null or _boost_meter.try_spend_tank())`.
   - A refused press spends no tank and does not fall into the default branch: the existing `if drive != null:` structure already prevents that.
   - `can_activate()`'s lockstep comment in `engine_boost_module.gd` is updated: the player-side efficiency guard is the caller's, checked before the spend.
2. **Default press:** `boost_efficiency() >= MIN_BOOST_EFFICIENCY` joins the start condition before the meter check. A refused press makes no velocity write and no drain.
3. **Boost speed:** `boost_speed(eff) = max_speed + (boost_exit_speed − max_speed) × eff` (the excess rule with floor `cruise_speed()` = `max_speed`), used at the start and in the sustain (× `hazard_speed_factor()` as today).
   The ceiling becomes `_speed_ceiling = boost_speed(eff)`.
   - A disrupted boost therefore buys a smaller burst but never slows the ship below cruise. At 0.4 it is 420 + 280 × 0.4 = 532 px/s, against 700 undisrupted.
   - The meter's drain is unchanged, so a disrupted boost costs as much and buys less. That is the "efficiency".
4. **Sustain:** if the efficiency drops below the floor mid-boost (an EMP lands), the boost stops on that tick exactly as the empty-meter stop does. There is no drain and no
   velocity write that tick.
5. Cruise (not boosting), the tail clamp, thrust, turning and firing are **never** touched (§6.6's principle: basic movement and primary fire stay).

**Boost Drive** (`global/ship_modules/engine_boost_module.gd`):
- `try_activate(player)` refuses when the player duck-types `boost_efficiency()` below the floor. This is the Assault H-key path (`player_fighter.gd::_input`), which
  spends nothing before calling it.
- Its burst speeds (`_BOOST_SPEED` 1500 at the start and `_BOOST_END_SPEED` 500, the eased re-assert in `tick()`) follow the excess rule with floor
  `player.cruise_speed()`, with the efficiency read once at activation. At 0.4 in Open Space: start 420 + 1080 × 0.4 = 852, end 420 + 80 × 0.4 = 452 px/s. In Assault
  (floor 360): 816 and 416 px/s. Both Drive speeds are above both floors, so the rule never raises a speed.
- A ship without the hook (`has_method` false) is unchanged.

**Assault dash** (`assault/scenes/player/states/dash_state.gd`):
- `start_state_transition()`: below the floor the dash, and the warp, are refused the same way the cooldown refuses (owner question 5 covers the warp).
- `process_physics`: the roll speed is `move_speed + (dash_speed − move_speed) × efficiency`, then × the hazard factor as today. At 0.4: 180 + 170 × 0.4 = 248 px/s
  (undisrupted 350), never below the dash's own lateral `move_speed` 180. The lateral steering inside the dash is unchanged.
- `_execute_warp(dir)`: distance `_WARP_DISTANCE × efficiency` (120 × 0.4 = 48 px).

**Readability:**
- The Open Space `BoostBar` tints violet and flickers while `efficiency < 1`, connected to `boost_disruption_changed`.
- Both ships show a small violet spark ring (a code-built `Line2D` ring, no PNG) for the duration.

**Tests (`tests/integration/test_player_boost_disruption.gd`, new, dual-mode: the real `player_ship.tscn` and the real Assault fighter, set up as `test_player_hazards.gd` does):**
- Default efficiency is 1.0. After `apply_boost_disruption(0.6, 2.5)` it is 0.4 until 2.5 s, then 1.0 ± 1 tick.
- Two disruptions give the stronger strength and the longer time, never the product.
- The signal is emitted with its arity on both players.
- **Open Space default boost:**
  - `_step_boost(true, true, dt)` at strength 0.6 → speed `max_speed + (boost_exit_speed − max_speed) × 0.4` ± 1 px/s, and the meter drains as undisrupted.
  - At strength 0.9 (efficiency 0.1 < 0.15) → refused: velocity unchanged, `charges` unchanged (boundary).
  - The efficiency drops to 0 mid-boost → the boost ends that tick with no drain on that tick.
- **Open Space Boost Drive (B4):**
  - With the Drive equipped and strength 0.9, a Shift press spends **no tank** (`charges` and the tank count unchanged), and `engine_boost_active` stays false.
  - At strength 0.6 the press spends one tank, the burst starts at 852 ± 1 px/s and its eased tail ends at 452 ± 1 px/s, never below `max_speed` 420 (the excess rule).
- **Assault:**
  - the dash speed is 248 ± 1 px/s at strength 0.6 (≥ `move_speed` 180); at 0.9 the dash is refused;
  - with the Warp module the blink moves 48 ± 0.5 px at 0.6, and 0 px (refused) at 0.9;
  - the H-key Boost Drive is refused at 0.9, and at 0.6 starts at 816 ± 1 px/s (floor 360);
  - `cruise_speed()` returns 420 (Open Space) and 360 (Assault).
- **Controls:** cruise thrust and the cruise ceiling are unchanged while disrupted, in both modes.

### 2.7 The pulse mine

**PULSE** (`mines/pulse_mine.tscn`):
- Its detonation calls `apply_boost_disruption(disrupt_strength 0.6, disrupt_seconds 2.5)` on every node in group `player` whose centre is within `pulse_radius` 170.
  - The helper is `EnemyMine._disrupt_players(radius, strength, seconds)`. It uses the `Hazards.pulse_damage` centre-distance shape and duck-types `has_method`.
- It also deals a small blast: `blast_damage` 8, `blast_radius` 48 (`ContactBlast` for PLAYER, `pulse_damage` for ALL).
- Look: an expanding violet ring over 0.3 s (a code-built `Line2D`, self-freeing in the parent container on its own clock). The violet effect ring shows during the warning.

**Tests (in `test_enemy_mines.gd`, both harnesses, with the real player of each mode):**
- A PULSE mine set off with the player inside 170 px disrupts it (`boost_efficiency()` 0.4).
- With the player at 180 px it does not (boundary).
- The player takes 8 damage from the blast, not 30.

### 2.8 EMP hook stub and the EMP mine

**`EmpPulse`** (`global/components/emp_pulse.gd`, `class_name EmpPulse extends RefCounted`, static):
- `emit(tree: SceneTree, at: Vector2, radius: float, seconds: float, source: Node) -> int`.
- It calls duck-typed `apply_emp(seconds, source)` on every node in group `player` whose centre is within `radius`, and returns how many were reached.
- Phase 9 extends the target set (enemies, the player's seeking weapons) and keeps the signature. **It is the one EMP entry point:** Ph9's EMP Pulse weapon and any jammer call it.

**On `PlayerBase`:**
- `apply_emp(seconds: float, source: Node) -> void`: `_emp_left = max(_emp_left, seconds)` (stepped in `_step_disruption(delta)`), and emits `emp_changed(active: bool)` on start and end.
- `is_emp_disrupted() -> bool`.
- **Phase 7's stand-in effect** is `apply_boost_disruption(1.0, seconds)`: efficiency 0, so the boost, the Boost Drive, the dash and the warp are all refused for the window
  (owner question 2).
- A comment marks the stand-in body as Ph9's to replace. Ph9 changes the body, not the signature.

**EMP mine** (`mines/emp_mine.tscn`):
- No hull damage: `blast_damage` 0, so no `ContactBlast` is spawned and no `pulse_damage` is dealt.
- Its detonation calls `EmpPulse.emit(get_tree(), global_position, emp_radius 190, emp_seconds 2.0, self)`.
- Look: a blue-white crackle ring over 0.35 s (code-built `Line2D`).
- No Mine Layer weight by default. Placed fields use it.

**Tests:**
- **`tests/unit/test_emp_pulse.gd`, new:**
  - reaches a stub with `apply_emp` inside the radius and not one outside it (boundary at radius ± 1);
  - returns the count;
  - ignores nodes without the method;
  - never touches group `enemies` in Ph7 (a stub enemy with `apply_emp` is not called; Ph9 flips this row).
- **`test_player_boost_disruption.gd`** (both players):
  - `apply_emp(2.0, null)` → `is_emp_disrupted()` and `boost_efficiency() == 0.0` for 2.0 s ± 1 tick;
  - boost, Boost Drive, dash and warp are refused, and no tank is spent;
  - `emp_changed(true)` then `(false)`.
- **`test_enemy_mines.gd`:** an EMP mine set off near the real player, in both harnesses, reaches it and deals no Health damage.

### 2.9 Mine art and readability

**Assets.** One PixelLab sprite per variant, under `assault/assets/sprites/projectiles/mines/`:
- `mine_proximity.png`, `mine_drifting.png`, `mine_homing.png` (+ `mine_homing_eye.png`), `mine_chain.png`, `mine_pulse.png`, `mine_emp.png`;
- `minefield_beacon.png`, a warning buoy of ≈ 24 × 32.

**Generation rules:**
- 24 × 24 px source, **strict top-down** (`view: "high top-down"`, `isometric: false`), generated under the `pixel-art-generation` skill.
- A visual check on every image. Saved through `scripts/pixellab.sh`.
- Each sprite keeps a transparent margin, so `test_entity_sprite_transparency.gd` (≤ 90 % opaque) passes. If a generated sprite has a painted-in glow, draw it by script
  instead (the Ph4 plate lesson).

**Readability rules (IDEAS §21–23):**
- **Faction palette:** dark hull, cool dark-blue edge light, one red faction mark.
- **One silhouette per variant:**
  - proximity: round, spiked;
  - drifting: round, two fins and a tiny nozzle;
  - homing: a single sensor lens;
  - chain: hexagonal, three linked prongs;
  - pulse: a coil ring around a violet core;
  - EMP: a small dish or antenna, blue-white core.
- **Gameplay light is drawn on top, never painted in:**
  - red slow blink = armed;
  - yellow fast blink + blast ring = warning;
  - violet (pulse) / blue-white (EMP) ring = effect radius, shown during the warning;
  - chain fuse links.
- The Bomber's mine (PROXIMITY) gets the proximity sprite: one family, one look.

**Scene changes:**
- Each mine scene gains a `Sprite` (`Sprite2D`) child. `_draw()` stops drawing the body circle when `Sprite.texture` is set.
- `body_color` is removed from the mine scenes (look-only), as Ph5 did for rockets.
- **This task owns the minefield beacon:** it replaces `Minefield`'s code-drawn placeholder beacon with `minefield_beacon.png`, so the minefield task must land first.

**Tests:**
- `test_enemy_mines.gd`: every variant scene has an opaque `Sprite` at its centre (the Ph5 rocket art row shape).
- The transparency sweep is green.
- `test_hazard_art.gd` gains the beacon (opaque centre, transparent corners).

### 2.10 Minefields as structures

**`Minefield`** (`assault/scenes/hazards/minefield/minefield.gd` + `minefield.tscn`, `class_name Minefield extends Node2D`, with `HAZARD.md`): a visible placed structure,
never an invisible collider. A single standalone mine needs no field: a `placed = true` mine works on its own (§2.1).

**Exports:**
- `pattern: Pattern { AUTHORED, RING, GRID, SCATTER }`.
- `count` 9, `radius` 200, `spacing` 110, `rng_seed` (0 = fixed 1).
- Flat weights `w_proximity` 1.0, `w_drifting`, `w_homing`, `w_chain`, `w_pulse`, `w_emp` (all 0 by default).
- `hostility` (default `ALL`; owner question 1).
- `drift_leash` 120. Each placed DRIFTING mine gets `drift_direction = Vector2.from_angle(rng.randf() × TAU)` from the field's seeded rng, and this leash.
- `assault_drift_speed` 60.

**Building the field:**
- AUTHORED uses the `EnemyMine` children placed in the editor under `Mines`. Godot readies those children *before* the field, so the field's `_ready()` sets `placed = true`
  and its `hostility` on each of them, and the mines' own placed setup is deferred to `_start_if_placed()` (§2.1 rule: queued by every mine's `_ready()`, runs after the
  whole add). A non-`EnemyMine` child under `Mines` is a `push_error` and is ignored.
- RING / GRID / SCATTER instance mine scenes from `EnemyMineScenes` into `Mines` in `_ready()`. That is load-time, not inside a physics flush. The variant per mine is
  drawn from the weights with the field's rng.
- A runtime spawn uses `spawn_into(container, at)`, the Ph6 deferred entry.
- **Every mine the field holds:** `hostility` = the field's, `placed = true` (self-owned, never fizzles, registers on its own launch; §2.1).

**Beacon:** a `Beacon` node marks the field with an amber `StateLight`-style blink. Until the art task (§2.9) it is a code-drawn amber placeholder. It goes dark when the last
mine is gone, and the field frees itself one second later.

**Modes:**
- In Open Space the field is still (its drifting mines move inside their leash).
- In Assault (an `assault_arena` provider exists) the field node moves itself down at `assault_drift_speed`. That is the wreck precedent, standing in for scrolling. The
  field frees itself once it is below `EnemyWorld.projectile_world_rect(tree)`, or after 40 s.
- No level-1 placement (Ph15 places Assault hazards).

**What enemies do at a placed field** (measured, §2.3): avoidance ≥ 0.8 never set it off (closest ≥ 155 px to a mine centre). 0.6 skirts it at 96–130 px and can graze it
with a large hull. The 0.5 Ram grazes it at 68–114 px. A ship with avoidance 0 flies straight in. That is the lure.

**Tests (`tests/integration/test_minefield.gd`, new; dual-mode where marked):**
- RING with `count` 9 lays 9 mines on a 200 px circle (± 0.5 px). GRID keeps its spacing.
- SCATTER is seed-stable: the same seed gives the same points, a different seed different ones.
- AUTHORED keeps the editor positions, and children authored with `placed = false` and PLAYER hostility end up `placed` and ALL after one frame (the ready-order
  boundary).
- Every placed mine is ALL and `placed`, never fizzles (60 s hand-ticked) and is registered.
- Placed DRIFTING mines move, and stay within 120 + 1 px of their placed point over 60 s.
- The field frees after its last mine.
- **Both modes, 8× real physics.** `fixture_enemy.tscn`'s `HurtBox` ships with no shape and the fixture joins no group, so the test adds a `CollisionShape2D` with a 14 px
  `CircleShape2D` to each fixture's `HurtBox` and calls `add_to_group("enemies")`, both at runtime before `add_child` (the shared fixture scene is not edited):
  - a player stub driven through the field is set off by a mine;
  - a `fixture_enemy` with `hazard_avoidance` 0 driven through it is set off and damaged;
  - a `fixture_enemy` with `hazard_avoidance` 0.8 and `hazard_margin` 24, seeking a target straight across the field at 240 px/s from lateral 0 / 100 / 200, sets off no
    mine, and its closest approach to every mine centre is ≥ 140 px (measured ≥ 155).
- **Assault:** the field moves `60 × t` down, frees past the world rect, and its mines' `HazardInfo.position` follows.
- `test_hazards.gd`: a field adds `count` to `Hazards.count()` and removes them when it is freed.

### 2.11 Mine Layer shell

**Files** (`assault/scenes/enemies/mine_layer/`):
- `mine_layer.tscn`, `mine_layer.gd` (`MineLayer extends BaseEnemy`), `mine_layer_brain.gd`;
- `mine_layer_config.gd/.tres` (`MineLayerConfig extends ShipConfig`, flat, `@export_group`s);
- `ENEMY.md`.

**Scene:**
- Body `CircleShape2D` r 40, shared by the body, the root `HurtBox` (hurtbox ≤ body, the Ph6 rule) and the `ContactHitBox` (mask 128).
- Size class 80–112 px: the art is ≈ 96 px.
- A `Dispenser` `Marker2D` at the stern, local (0, −38). The art is nose-down, so +y is forward.
- A `StateLight`.
- `EnemyMover` + `MineLayerBrain`.
- `MineLayer._ready()` calls `add_to_group("enemies")`, as every shipped enemy does (`BaseEnemy` does not). Placed (ALL) mines rely on it.
- `ContactProfile` mode COLLISION (`collision_damage` 25).
- One root `BulletPool` per variant with weight > 0 (`ProximityPool`, `ChainPool`, `PulsePool`, `HomingPool`; `DriftingPool` / `EmpPool` only if their weights are raised).
  Each has `persist_after_owner_death = true`, is sized in the scene, and is gated equal to `EnemyMineScenes.pool_size_for()`.
- Placeholder hull art (`bomber.png` scaled) until §2.13.

**`MineLayerConfig` (flat; `.tres` values; the passes task adds its own group):**
- **Scoring / Defense:** `max_health` 140, `collision_damage` 25, `score_value` 60.
- **Movement:** `max_speed` 240, `acceleration` 420, `max_turn_rate` 2.4, `lay_speed` 170, `exit_speed` 300.
- **Hazards:** `hazard_avoidance` **0.8**, `hazard_margin` 24, `hazard_resistance` 0.2. Wreck: `wreck_chance` 0.35, `wreck_size` medium, `explosive_wreck_chance` 0.
- **Mines:**
  - `mine_arm_delay` 0.5, `mine_eject_speed` 120, `mine_eject_time` 0.3;
  - `assault_mine_life` 9.0, `open_space_mine_life` 0.0 (persists), `open_space_mine_backstop` 240.0;
  - `max_live_mines` 18, `assault_max_live_mines` 8;
  - `w_proximity` 0.5, `w_chain` 0.2, `w_pulse` 0.15, `w_homing` 0.15, `w_drifting` 0.0, `w_emp` 0.0.
  - **No `trigger_radius`, warning or blast fields:** the variant scenes own those (§2.2).
- **Engagement:** `engage_seconds` 9.0 (Assault budget).
- **Rail:** `rail_mine_interval` 1.6.

**`MineLayer.drop_mine(variant, rest_point) -> EnemyMine`:**
- Acquires from the variant's pool at the `Dispenser`. It falls back to `ProximityPool` when that pool is absent or exhausted.
- **Sets only:** `arm_delay = config.mine_arm_delay` and `eject_time = config.mine_eject_time`, plus the life by mode (Assault when `EnemyWorld.arena(tree)` exists):
  - Assault: `mine_life = assault_mine_life`;
  - Open Space: `mine_life = open_space_mine_life` and the `ProjectileLifetime.max_time = open_space_mine_backstop`.

  It **never** writes `trigger_radius`, `warning_time`, `blast_radius` or `blast_damage`, so PULSE keeps 8 and EMP keeps 0.
- Launches toward `rest_point` at `2·|rest − pos| / mine_eject_time`, so it stops on the point (the Bomber's eject rule, within 4 px).
- Returns null if nothing was acquired.

**Brain shell:**
- `Phase` is declared in full (*For every task*). This task plays only APPROACH (seek the player at `max_speed`) and DISENGAGE (exit at `exit_speed` along the current
  heading, the Bomber's exit).
- `start_engaged` seam.
- `accepts_tow()` refuses in LAY.

**Rail fallback** (mandatory, the Ph3/Ph4 rule): `on_suspended()` starts a `_process` clock on `MineLayer` that drops a PROXIMITY mine at the `Dispenser` (speed 0) every
`rail_mine_interval`, with life `assault_mine_life`.

**Roster gates:**
- Add the scene to the hand-maintained rosters: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, and
  **`test_wreck.gd`'s `_SHIP_SCENES`** (the "no hurtbox larger than its body" list is a hand list, `test_wreck.gd:33-44`).
- `test_config_instance_isolation.gd` picks it up by its directory sweep.

**Tests (`tests/integration/test_mine_layer.gd`, new):**
- Pool sizes equal `pool_size_for`.
- `drop_mine` in each mode:
  - Assault: life 9.0;
  - Open Space: life 0 with backstop 240;
  - `arm_delay` 0.5 and `eject_time` 0.3 in both.
- **Per-variant numbers survive the drop (M2):** after `drop_mine` the mine's `trigger_radius`, `warning_time`, `blast_radius` and `blast_damage` equal its scene's exports
  (`export_of`), so PULSE is 8.
- The eject stops within 4 px of the rest point.
- An exhausted CHAIN pool falls back to PROXIMITY.
- The pools hand over on the layer's death: a mine laid before the death still triggers after it.
- The rail fallback drops at 1.6 s ± 1 tick on a real `EnemyPathMover`.
- `accepts_tow()` is false in LAY.
- The case in `test_enemy_dual_mode.gd`: APPROACH closes on the player in both modes, inside the corridor in Assault.

### 2.12 Mine Layer passes (the combat AI)

**What it does:** the layer flies *sideways across* the player's path, laying one zig-zag or curved line of six mines. It breaks off, waits at a standoff, and lays the next line
somewhere else. In Open Space the gap from the end of one line to the start of the next is at least `break_seconds + pass_period_min` = 6.2 s. With a line taking ≈ 3.9–4.3 s
to lay, that is one line every ≈ 10–14 s. It never fills the screen.

**Player frame:**
- P = the player's position (`TargetInfo.position`).
- v̄ = smoothed velocity: an exponential average with `velocity_smoothing` 0.5 s, the Bomber's `smoothed_velocity()` shape.
- f = v̄ / |v̄| when |v̄| ≥ `frame_speed` 60, else the unit vector from P toward the layer.

**Pass geometry (`plan_pass()`, re-planned every tick in APPROACH until frozen).** All lengths in px:
- Axis `u = f.orthogonal()`, signed so that S, the start end, is the end nearer the layer. `n̂` = the unit normal of the axis pointing from C toward P (in Assault: toward the
  player's side of the line).
- `L = pass_length` 600 (both modes). `S = C − u·L/2`, `E = C + u·L/2`.
- **Run-in point** `R = S − u·run_in` (`run_in` 150): the layer reaches the line's axis at R and flies R → S along u before laying, so it is already sideways at S
  whatever direction it arrived from.
- **Rest points**, `n = mines_per_pass` 6, half-wavelength `h = mine_step` 100. Mine k (k = 0..5) sits at axis coordinate `x_k = (k − 2.5)·h` (−250 … +250), offset
  `y_k` along `n̂`:
  - **ZIGZAG** (mines on the vertices): `y_k = +A` for even k and `−A` for odd k, with `A = zigzag_amplitude` 35. Each chord is √(100² + 70²) = 122.1 and runs at
    atan(70/100) = 35.0° to u.
  - **ARC** (a bow toward P): `y_k = 4·arc_depth·t·(1 − t)` with `t = k/5` and `arc_depth` 110. That gives 0, 70.4, 105.6, 105.6, 70.4, 0. The chords are 122.3, 106.0,
    100.0, 106.0 and 122.3, and the steepest runs at atan(70.4/100) = 35.1° to u.
  - The shape is drawn from `brain.rng` with `arc_chance` 0.5, once per pass.
- **Path:** the polyline S → mine 0 → … → mine 5 → E (a 50 px lead-in and lead-out along the axis). Its length is ≈ 732 for ZIGZAG and ≈ 657 for ARC.
- **Variants:** one per mine from the flat weights by `rng`, at most one HOMING per pass.
- **Open Space no-stacking:** a rest point within `trigger_radius + 40` (120) of a live mine is skipped.
- **Spread (Open Space):** a new C must be ≥ `min_pass_separation` 380 from the centre of every earlier pass that still has a live mine. The candidates, in order, are C
  itself, then C rotated about P by +θ, −θ, +2θ, −2θ, with `θ = 2·asin(min(1, (min_pass_separation + 10) / (2·|C − P|)))`: the rotation that moves C by 390 px
  (75.1° for a standing player, `|C − P|` = 320). S, E, R and the rest points are rebuilt from the chosen C. If no candidate is legal the first one is used,
  `spread_fallbacks` is incremented, and a verbose-gated line is logged.

**Lead (the Ph4 wall rule, undamped, on the layer's own timeline):**
- `t_lead = t_approach_left + min(c, lead_horizon)`. Only `c` is capped, as in Ph4 (`DECISIONS.md`, Phase 4 t10).
  - `t_approach_left = |R − pos| / max_speed + run_in / lay_speed` (to the run-in point, then the run-in; 150 / 170 = 0.88 s);
  - `c = (L/2) / lay_speed + mine_arm_delay` = 300 / 170 + 0.5 = 2.26 s;
  - `lead_horizon` 3.0.
- Centre C:
  - moving player: `P + v̄·t_lead + f·ahead_distance` (260);
  - standing player: `P + f·fence_distance` (320), so the fence goes between the player and the layer.
- **Recorded departure from Ph4:** the Bomber's `c` adds `wall_margin + (trigger_radius + arc_depth) / |v|` (a time). The layer instead places C `ahead_distance` 260 px ahead
  along f (a distance), and freezes the plan within `commit_distance`. The "C is ahead of the live player when the middle mine arms" row proves the shape.

**Assault ("clamped to the corridor"):**
- u is forced horizontal (±x), with S on the side the layer is on.
- C.y = P.y − `assault_ahead` 220.
- C, S and E are clamped into `EnemyWorld.view_rect(tree).grow(−(view_margin 64 + max(zigzag_amplitude, arc_depth)))` = `grow(−174)`. That leaves a 932 × 372 box for a
  600 px line, so every mine lands inside `view_rect().grow(−64)`.
- The `AssaultCorridorConstraint` still filters the flight.

**Phases:**
- **APPROACH** has two steps, both inside the APPROACH phase (no new enum value):
  1. **Seek R** at `max_speed`, re-planning every tick. The plan is frozen once the layer is within `commit_distance` 200 of R.
  2. **Run-in:** pure pursuit along the segment R → S at `lay_speed`, aiming `path_lookahead` 60 px ahead (the LAY rule). When the layer's centre passes S (its
     projection on u reaches S), the phase becomes LAY.

  Measured by the plan reviewer (pure pursuit, 420 px/s² acceleration, 150 px run-in): from S on, the heading stays ≤ 33° from u and the centre ≤ 23 px from the path,
  even for an arrival at R perpendicular to u at 240 px/s. Without the run-in that arrival gave 89° and 73 px.
  - In Assault, budget expiry anywhere in APPROACH (run-in included) → DISENGAGE. R lies inside the view: S is clamped ≥ 174 px inside it, so R is ≥ 24 px inside.
  - **Approach give-up (Open Space only):** a layer behind a fast player cannot get ahead of it (240 px/s against a 220 px/s player closes at 20 px/s). If APPROACH has
    lasted `approach_max_seconds` 6.0 s without freezing, the brain re-plans once in the **fence form** (f = the unit vector from P toward the layer, C =
    P + f·`fence_distance`, the standing-player rule), runs the spread check, and **freezes that plan at once**. `fence_fallbacks` is incremented. The line then lies
    between the player's position at that moment and the layer: area denial behind a fleeing player, which in Open Space persists for when the player returns.
- **LAY** (committed; `accepts_tow()` false):
  - Pure pursuit along the polyline, aiming `path_lookahead` 60 px ahead, at `lay_speed`.
  - **Drop timing (the Bomber's "plus" rule, measured at the Dispenser):** mine k is dropped through `drop_mine` once the Dispenser's path coordinate has passed mine k's
    path coordinate by the eject lead `mine_eject_speed × mine_eject_time / 2` (18). The Dispenser sits 38 behind the centre, so the centre is then 56 past it. The mine
    ejects back 18 px onto its point.
  - The `StateLight` goes CHARGING for 0.3 s before each drop. The dispenser hatch is open for the whole of LAY (§2.13).
  - Whatever was not dropped by the end goes at the end, so a pass always delivers its pattern.
  - Stall guard: `path_length · 1.2 / lay_speed + 0.5` s, ≤ 5.67 s (ZIGZAG).
  - The Assault budget defers to the end of LAY. A telegraphed attack is never cut off; the deferral bound is that stall guard.
  - Avoidance stays on during LAY. The layer's fresh mines are behind it (outside the 112.5° inside-cone of its heading), so they do not deflect it. If the "stays on its
    path" row fails because of an older pass's mines, **pre-approved lever:** LAY drives the mover through `boost(dir, lay_speed, delta)` each tick (Ph6's committed-run
    bypass). Record it if used.
- **BREAK_OFF:** `mover.break_contact(P, v̄, side, break_speed 260)` for `break_seconds` 1.2, with `side` pointing away from the fresh line. Assault: DISENGAGE instead (one
  pass per life).
- **REPOSITION** (Open Space): orbit P at `standoff_range` 600, direction drawn per pass, for a period drawn from `pass_period_min..max` 5.0–7.0 s. Then APPROACH.
- **DISENGAGE:** continue along u (sideways, off the far side) at `exit_speed`. **With no planned pass** (a layer put into DISENGAGE directly, as `SpecialistExitProbe` and the
  shell's own rows do) it exits along its current heading: the velocity direction, or the facing when the velocity is zero. That is the exit
  `SpecialistExitProbe` measures.
- **Tail drop (any engaged phase except LAY):** if the player is within `tail_range` 280 and inside the rear `tail_cone_deg` 60° cone, drop one PROXIMITY mine at the Dispenser
  with no eject, at most every `tail_drop_cooldown` 2.5 s. Chasing a Mine Layer is dangerous.
- **Live cap:** the brain keeps a FIFO of live mines (instance ids; dead ones are pruned). Before a drop at `max_live_mines` (Assault `assault_max_live_mines`) it `retire()`s
  the oldest (owner question 3). Nobody counts a dead layer's handed-over mines.

**Config fields this task adds:**
- `velocity_smoothing`, `frame_speed`;
- `pass_length`, `mine_step`, `mines_per_pass`, `zigzag_amplitude`, `arc_depth`, `arc_chance`;
- `ahead_distance`, `fence_distance`, `assault_ahead`, `lead_horizon`;
- `run_in`, `commit_distance`, `path_lookahead`, `min_pass_separation`, `approach_max_seconds`;
- `break_speed`, `break_seconds`, `standoff_range`, `pass_period_min`, `pass_period_max`;
- `tail_range`, `tail_cone_deg`, `tail_drop_cooldown`, `view_margin`.

**Test seams:** `pass_centre`, `pass_start`, `pass_end`, `pass_run_in_point`, `spread_fallbacks`, `fence_fallbacks`, `freeze_plan()` (freezes the current plan,
for the arrival rows), `pass_axis`, `pass_normal`, `pass_shape`, `planned_rest_points`, `drops_this_pass`, `passes_started`,
`live_mine_count()`, `smoothed_velocity()`, `plan_pass()`.

**Tests (`test_mine_layer.gd` + cases in `test_enemy_dual_mode.gd`; hand-ticked with `_tick()`; the shared scenario computed once in `before_all`):**
- **Trail placement, both modes:**
  - ZIGZAG: consecutive rest points are 122.1 ± 2 apart, their offsets along `n̂` alternate sign with |y| = 35 ± 1, and their axis coordinates step by 100 ± 1.
  - ARC: each rest point is within 2 px of `C + u·x_k + n̂·y_k` from the formula, every offset is ≥ −0.5 (on P's side), and consecutive spacing is within [98, 125].
  - Every mine ends within 4 px of its planned point.
  - In Assault every mine lies inside `view_rect().grow(−64)`, and the axis is horizontal (|u.y| < 0.01).
- **Lead:**
  - For a stub moving at 220 px/s, C is more than `trigger_radius` (80) ahead of the live player's position (projection on v̄) at the moment the middle mine arms.
  - For a standing stub, C is between it and the layer.
  - For a stub reversing at LAY start, the line is still where it was planned (frozen).
- **Run-in:** in APPROACH after the freeze the layer heads for R, then follows R → S. LAY starts when its centre passes S, never before. No mine is dropped before LAY.
- **Sideways (from S on):** during LAY, the layer's velocity is within 40° of ±u. Asserted for an aligned arrival **and for an arrival at R perpendicular to u**: a plan frozen
  with `freeze_plan()` while the layer sits 300 px from R along n̂ moving toward R at 240 px/s (the case that gave 89° without the run-in; measured ≤ 33° with it).
- **Stays on its path (from S on):** during LAY, the layer's centre stays within 40 px of the polyline, for the same two arrivals, and also in a scenario with an earlier
  pass's mines 380 px away.
- **Gradual (Open Space, two 60 s scenarios, each computed once in `before_all`):** a **standing** stub, and a stub **moving at 220 px/s** on a 700 px-radius circle (so the
  layer stays in play). In both:
  - the gap from the end of each LAY to the next LAY start is ≥ 6.2 s;
  - each pass drops ≤ 6 mines;
  - **for every plan that did not take the spread fallback**, its centre is ≥ 380 px from every earlier pass centre that had a live mine when it was planned (the
    `spread_fallbacks` count is logged per scenario);
  - the live count never exceeds 18, and the 19th drop retires the oldest (boundary).
- **Spread, pure `plan_pass()` rows (standing player, layer at 600 px on bearing 0°):**
  - earlier live centres at bearings 0° and ±75.1° on the 320 px circle → the new C is at +150.2° (the +2θ candidate), ≥ 380 from all three, `spread_fallbacks` unchanged;
  - earlier live centres at 0°, ±75.1° and ±150.2° → no candidate is legal: the plan uses C itself and `spread_fallbacks` rises by 1 (boundary).
- **Approach give-up (Open Space):** a layer started engaged 600 px directly behind a stub flying straight away at 220 px/s does not freeze a plan within 6.0 s, then
  freezes a fence plan (`fence_fallbacks` = 1), reaches LAY, and its C lies on the segment from the stub's position at that moment toward the layer, 320 ± 2 px from the
  stub. Control: the same stub with the layer starting 600 px ahead of it → `fence_fallbacks` = 0.
- **Assault:**
  - exactly one pass per life, then DISENGAGE sideways;
  - with the budget expiring mid-LAY, the pass completes (all 6 mines dropped) within the stall guard.
- **Tail drop:** a stub 200 px behind, in the cone, gets a mine within one tick and no second one before 2.5 s. A stub 200 px *in front* gets none (the control).
- `accepts_tow()` is false in LAY and true in REPOSITION.
- **Hazard-aware:** from the standing 60 s scenario, while the layer is in APPROACH (run-in included), REPOSITION or DISENGAGE, its centre's closest approach to every live
  mine of every pass other than the one currently planned is > 100 px. LAY and BREAK_OFF are excluded (when LAY ends the layer is ≈ 61 px from mine 5 of the line it
  has just laid, and BREAK_OFF is leaving it), and so are all tail-drop mines. The measured value for avoidance 0.8 against a laid line is ≥ 149 (§2.3). The same scenario with its mines'
  `registers_hazard = false` is logged as the control, not asserted.

### 2.13 Mine Layer art, dispenser state and wake trail

**Hull:** `assault/assets/sprites/enemies/mine_layer.png`, a PixelLab `create_map_object`:
- strict top-down (`view: "high top-down"`, `isometric: false`), ≈ 96 × 96;
- nose-down (`sprite_forward_angle` default `PI/2`);
- a wide, flat specialist hull with a visible rear mine rack;
- dark hull, cool edge light, red faction stripe, no painted glows or flames.

Generate several candidates and pick the best (CLAUDE.md's "use PixelLab freely" rule), with a visual check on each, through the `pixel-art-generation` skill and
`scripts/pixellab.sh`.

**Dispenser hatch** (§23: "every specialist has a readable state change"): `mine_layer_hatch.png`, a sprite over the rack.
- Its `scale.y` eases from closed to open over 0.25 s when LAY starts, and closes on leaving LAY.
- `MineLayer.set_hatch_open(0..1)` is driven by the brain. The Godot zero-scale epsilon applies, so tests compare with a tolerance.

**Wake trail:** `MineWake` (`mine_layer/mine_wake.gd`), a code-built `Line2D` added to the layer's parent container at LAY start.
- It appends the `Dispenser`'s global position every 12 px during LAY: width 3, dark-red → transparent gradient, alpha 0.45.
- It fades over `wake_fade` 2.5 s after LAY ends, then frees itself on its own clock. That is the `RailTrail` precedent; it never uses `create_timer`.
- It shows where the line of mines was just laid.

**Tests (`test_mine_layer.gd`):**
- The hull sprite is opaque at the centre and transparent at the corners.
- The hatch is closed outside LAY and open during it.
- The wake has ≥ 2 points per 24 px laid, lies within 4 px of the dispenser's path, and is freed 2.5 s ± 1 tick after LAY ends.
- The transparency sweep is green.

### 2.14 Mine Layer hub idle and Open Space persistence

**Idle:** the Ph4/Ph5 template.
- `AnchorIdle` runs ahead of the phase dispatch: `patrol_anchor` (default = spawn), `idle_phase_offset` from `rng`, `start_engaged`.
- IDLE / NOTICING / RETURNING are appended, with their values fixed by the enum in *For every task*.
- Assault builds no `AnchorIdle`; `on_suspended()` drops it.
- **Not interruptible by RETURNING:** LAY. The return is retried every tick.
- NOTICING redraws the pass period, so a layer that idled for a minute does not lay the instant it notices.
- Idle never lays and never tail-drops.

**Idle config group:**
- `perceive_radius` 650, `lose_radius` 1500, `notice_time` 0.35, `idle_radius` 160, `idle_speed` 0.5.
- **Two inequalities, asserted from the config** (`MineLayerConfig` values, never typed numbers). Together they mean the layer's own cycle never sends it home mid-fight
  **against a player flying at ≤ 220 px/s**:
  1. the cycle: `lose_radius > standoff_range + break_speed × break_seconds + pass_length / 2 + run_in`, i.e. 600 + 312 + 300 + 150 = 1362 < 1500;
  2. the lead, at `v = 220`: `√((v·t_lead + ahead_distance)² + (pass_length / 2 + run_in)²) + commit_distance < lose_radius`, with
     `t_lead = commit_distance / max_speed + run_in / lay_speed + min((pass_length / 2) / lay_speed + mine_arm_delay, lead_horizon)` = 0.83 + 0.88 + 2.26 = 3.98 s,
     i.e. √(1135.7² + 450²) + 200 = 1421.6 < 1500.
- **A faster player is let go on purpose.** A player cruising at full speed (420 px/s) puts R about 1900 px ahead, beyond `lose_radius`, and the layer (240 px/s) could
  never get ahead of it anyway. Losing that player and returning home is the intended outcome.

**Open Space persistence ("an area the player comes back to stays dangerous"):**
- Mines laid in Open Space have `mine_life` 0 and a backstop of 240 s.
- RETURNING does not touch them, and the layer's death hands them over.

**Tests (`test_mine_layer.gd`, Open Space harness):**
- The inequality row.
- Frame-0 IDLE.
- NOTICING after `notice_time` inside `perceive_radius`.
- RETURNING beyond `lose_radius` (the player stub **teleported** 1600 px from the layer, since `AnchorIdle` measures actor-to-target and a layer in REPOSITION follows a
  player who flies away), but not during LAY.
- **The persistence row** (hand-ticked, one shared scenario):
  - the layer lays a pass;
  - the player stub is **teleported** 2000 px from the layer (beyond `lose_radius` 1500 of the layer, not of the anchor), and the layer goes RETURNING and reaches home;
  - 60 s of game time later the player stub is placed 300 px short of the line and driven through it at 220 px/s;
  - every mine is still at its rest point and still registered, and the first one it reaches sets it off.
- The same row in Assault shows the mines gone after `assault_mine_life` (the mode difference, asserted).

### 2.15 Hub placement: Mine Layer patrol and a placed minefield

**Patrol spawn:**
- `SectorHub._spawn_patrol()` (`open_space/scenes/levels/sector_hub.gd`) appends `_spawn_mine_layer(_mine_layer_anchor(), rng)` **after** the existing 14 draws (draw 15),
  so every earlier seed is unchanged.
- New exports `mine_layer_ring_radius` 2600 and `mine_layer_anchor_bearing_deg` −22.5 give the anchor ≈ (2402, −995): north of the Gatling and east of the Missile
  Corvette, well away from the Ph6 `TacticalSpace`.
- `patrol_anchor` and a nonzero `rng_seed` are set before `add_child()`.

**Placed minefield:**
- `TacticalSpace/Minefield` at (3300, 560), north of the well–anomaly lane. The well (radius 420) edge is 49 px from the field's trigger edge, so the well's pull toward it is
  part of the place.
- RING, `count` 9, `radius` 200, `rng_seed` 7, `hostility` ALL.
- Weights `w_proximity` 0.4, `w_chain` 0.3, `w_drifting` 0.15, `w_emp` 0.15. The drifting mines ping-pong within the field's `drift_leash` 120 (§2.10).
- It is a lure: the player can pull patrols into it.

**Clearance (`tests/integration/test_sector_hub_patrol.gd`; the Ph6 rule, `docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md` §2.16):**
- **`_patrol_groups()` gains `"Mine Layer": [mine_layer_anchor, MINE_LAYER_CONFIG.idle_radius, MINE_LAYER_CONFIG.perceive_radius]`.**
- **`_element_radius()` gains a `Minefield` case:**
  `radius + (drift_leash if w_drifting > 0.0 else 0.0) + EnemyMineScenes.export_of(EnemyMine.Variant.PROXIMITY, &"trigger_radius", 80.0)`.
  `Minefield` has no `trigger_radius` of its own, so it is read from the proximity mine scene; a placed drifting mine can wander `drift_leash` from its ring point.
  For the hub field that is 200 + 120 + 80 = **400 px**. The existing `_space_clearance_violations()` sweep then applies the "> 100 px past every group's idle ring +
  perceive_radius" rule to the field. It also checks the "> 300 px from every interactable" rule.
- Computed for this layout (revision 3, from the scene's positions and the shipped configs): the minefield clears the Mine Layer group by 1796 − 400 − 810 = **586 px**
  and the Gatling group by **775 px** (the nearest two; rule > 100). The worst group-to-element clearance in the whole sweep stays 410 px, an existing element. The Mine
  Layer anchor clears the satellite by 1891 − 28 − 810 = 1053 px.
- **Mine Layer ring row:** the anchor clears every `MissionTrigger` / `PickupBase` and the player spawn by `idle_radius + perceive_radius`, with the margin printed.
- **Anchor spacing:** the anchors stay more than 1000 px apart. The Mine Layer's nearest is the Missile Corvette's at (1343, −1343), 1114 px away.
- The seed row, the container count and the frame-0 IDLE list gain the layer.
- A hub Mine Layer's mine lands in `EnemyContainer` (8×).

If a clearance row fails, the bearing, ring or field position moves (exports and the scene). No other group moves.

### 2.16 Level 1 placement

**Placement:** two Mine Layer lines, each **inside an existing wave of a DURATION section** (no new wave, so no other wave's effective trigger moves; read the Phase 3
"wave-order quirk"):
- `deep_space` wave 16.0 s: `b.mine_layer().at(-400, -160)`, entering from the left;
- `planet_approach` wave 47.0 s: `b.mine_layer().at(400, -160)`, entering from the right.

Both are AI spawns: no `.move()`, no `.free_after()`. Never in an `ENEMIES_CLEARED` section (mines persist).

**Gates:**
- **`test_level1_specialist_spawns.gd`:**
  - an `EXPECTED_PH7` pin (2 rows) and a row-count sanity check;
  - the Mine Layer counts as a specialist in the frozen 2.5× count gate. Deep Space's peak becomes 8 (it lands on the 7 at 15.50 s) of 12.5; Planet Approach stays ≤ 7.5;
  - its life is `engage_seconds + lay deferral (the stall guard, ≤ 5.67 s) + 2 ticks + measured exit`, the exit from `SpecialistExitProbe.worst_disengage()` over
    `corridor_starts()` at `[exit_speed, 10]`, measured once in `before_all`. The probe enters DISENGAGE with no planned pass, so the layer exits along its current
    heading (the brain's no-pass rule: velocity direction, else facing); the measured exit is therefore the real one. The life also covers the run-in, which sits inside
    the engagement budget (APPROACH);
  - spill-over row: the life plus `assault_mine_life` must end before the next `ENEMIES_CLEARED` section's last trigger. The mines count, as a corvette's rocket life does;
  - boundary: an extra Mine Layer at Planet Approach's measured peak fails the gate.
- **`test_engagement_deadline.gd`:** a "no `ENEMIES_CLEARED` section contains a Mine Layer" row, plus a boundary row: a Mine Layer added to cloud_descent's last wave computes
  over the timeout.
- **Attack-in-budget row (`test_mine_layer.gd`):** from each of the two level-1 spawns, through a real `WaveManager` (`tests/helpers/level1_slice_replay.gd`, window
  `rel − 1 s .. rel + engage + 7 s`, 8×), the layer reaches LAY before its budget expires, lays ≥ 4 mines inside `view_rect()`, and does one pass per life.

If a gate fails, the task moves its own line's offset or wave (within the same section), or escalates. No lever on another enemy is pre-approved.

### 2.17 Gate time

Phase 6 ended at **GUT 216.3 s** (wall 221.4 s) of the 240 s ceiling. Plan review round 1 re-measured 216.4 s (2139 tests).

**t1 (gate room) must free ≥ 12 s (GUT ≤ 204.4 s). That floor is hard.** If 12 s cannot be freed within the rules, t1 ends with `Result: ESCALATE` and the measured per-file
table, rather than letting later tasks start on a thin budget. Only the `tests/README.md` → Gate time rules are used:
1. **8× clock for rows still awaiting real physics at 1×.** The measured 1× real-physics files (round-1 review run) are:
   - `test_armor_query.gd` 5.3 s;
   - `test_station_laser_phase.gd` 4.9 s;
   - `test_station_assault_section.gd` 4.1 s;
   - `test_swarm_drone.gd` 3.6 s;
   - `test_station_incoming_damage_paths.gd` 2.7 s.

   That is ≈ 20.6 s, of which roughly 12–15 s is recoverable. A row whose tolerance is tighter than one idle frame at 8× (≈ 0.13 game-s; some station rows use
   `wait_seconds(0.1)`-scale tolerances) stays at 4× or 2× rather than widening its tolerance (rule 1). The station family asserts intent: its assertions are untouched.
2. **Compute a shared scenario once.** `SpecialistExitProbe` measurements (`test_engagement_deadline.gd` 6.1 s, `test_level1_specialist_spawns.gd` 4.6 s) may be memoised in
   the helper, keyed by their inputs (scene, speeds, start set), so the second file reuses the first's result in the same GUT process.
3. Drop per-tick bookkeeping no assertion reads.

It never lowers a tick count, duration, sample count or grid, never widens a bound, and never removes an assertion. Already on the 8× clock, so not candidates:
`test_wreck.gd`, `test_enemy_ordnance.gd`, `test_bomber.gd`'s real-physics rows. `test_player_hazards.gd` has no await.

A **behaviour-identical speed-up of production code is a last resort**, not a fourth rule. Use it only if rules 1–3 fall short, only with bit-identical outputs on every
existing row, and record it in `tests/README.md` as a rules change.

**Allotments (new GUT seconds; total 28.5 s):**

| Task | t2 | t3 | t4 | t5 | t6 | t7 | t8 | t9 | t10 | t11 | t12 | t13 | t14 | t15 | t16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Allotment (s) | 3.0 | 1.5 | 1.5 | 1.5 | 0.5 | 1.0 | 1.5 | 0.5 | 1.5 | 4.5 | 1.5 | 0.5 | 1.5 | 8.0 | 0 |

t11 has 4.5 s (revision 3: a second 60 s scenario, the arrival rows and the give-up row, all hand-ticked). So the phase ends ≤ 216.4 − 12 + 28.5 = 232.9 s.

**Costs:** a real-physics case at 8× ≈ 0.25–0.4 s, a hand-ticked dual-mode case ≈ 0.02–0.06 s, a slice replay at 8× ≈ 2–5 s.

### 2.18 Numbers and where they come from

No external research was done for this phase. Every number is an earlier phase's, a measurement, a derivation from another number, or a *starting value* (judgement,
not play-tested; tune in Ph16/Ph17 if needed).

| Number | Value | Origin |
|---|---|---|
| Mine trigger / warning / blast / damage | 80 / 0.25 s / 48 / 30 | Bomber mine (Ph4 t9–t10) |
| `arm_delay` | 0.5 s | Bomber mine |
| Warning band | 440 px/s | Ph4 `mine_speed_max` |
| `hazard_pad`, `avoid_weight` | 60, 1.0 | Measured (§2.3) |
| Mine Layer `hazard_avoidance` / margin | 0.8 / 24 | Measured (§2.3): the lowest level that keeps ≥ 145 px from a laid line |
| `home_speed` | 60 px/s | Derived: the largest round speed passing the warning rule (512 ≥ 440 + 60) |
| `notice_radius` / `home_lose_radius` | 260 / 380 | Starting value: notice = trigger + 180 (3 s of creep to reach the trigger); lose = notice + 120 hysteresis (the perceive/lose shape) |
| `home_max_distance`, `home_turn_rate` | 900, 2.0 rad/s | Starting value |
| `drift_speed`, `drift_max_distance` | 35 px/s, 1400 | Starting value (< 10 % of the 420 px/s cruise); 1400 = 40 s, the wreck's life |
| Field `drift_leash` | 120 | Starting value, about one mine spacing |
| `chain_radius`, `chain_delay` | 150, 0.2 s | Derived: 150 > the largest laid spacing (122.3) and < 2 × the step (200), so a laid line links and a skipped point breaks it; 0.2 s a hop is a starting value (a 6-mine ripple takes 1 s) |
| Pulse strength / seconds / radius | 0.6 / 2.5 s / 170 | Starting value (radius ≈ 2 × trigger) |
| EMP seconds / radius | 2.0 s / 190 | Starting value |
| `MIN_BOOST_EFFICIENCY` | 0.15 | Starting value |
| Pass geometry: step / amplitude / arc depth / mines / length | 100 / 35 / 110 / 6 / 600 | Derived: chord ≈ 122 at ≤ 35.1° (B2 fix); 6 × 100 − 100 + 2 × 50 lead = 600 |
| `lay_speed` / `max_speed` / `exit_speed` | 170 / 240 / 300 | Starting value, between the Bomber's run speed and the Missile Corvette's |
| `ahead_distance` / `fence_distance` / `assault_ahead` | 260 / 320 / 220 | Starting value; the lead row proves ahead > 80 |
| `lead_horizon` | 3.0 s | Bomber `mine_horizon` |
| `run_in` | 150 px | Measured by the round-2 plan review: the shortest run-in tried that keeps LAY ≤ 33° / ≤ 23 px from a perpendicular arrival |
| Spread rotation θ | `2·asin((380 + 10) / (2·|C − P|))`, 75.1° at 320 px | Derived: the chord that moves C 390 px (10 px over `min_pass_separation`) |
| `approach_max_seconds` | 6.0 s | Starting value: ≈ 2.7 × the ≈ 2.2 s a layer at the 600 px standoff needs to reach R for a standing player (√(280² + 450²) ≈ 530 px at 240 px/s) |
| Disruption floors | `cruise_speed()` 420 / 360; dash 180 | Existing exports: Open Space `max_speed`, Assault `MoveState.move_speed`, `DashState.move_speed` |
| `pass_period_min..max`, `break_seconds` | 5–7 s, 1.2 s | Starting value |
| `max_live_mines` / Assault | 18 / 8 | Starting value (3 passes / 1 pass + tail drops) |
| Assault mine life | 9.0 s | Bomber 8.0 + 1 s for the longer pass |
| Open Space backstop | 240 s | Starting value (a hub return trip) |
| `perceive_radius` / `lose_radius` | 650 / 1500 | Bomber perceive 650; lose from the inequality in §2.14 |
| Mine Layer HP / contact / score | 140 / 25 / 60 | Starting value, between the Bomber (150/35/80) and the Support Ship |
| Hub anchor | −22.5°, 2600 | Computed clearance (§2.15) |

### 2.19 Docs

Run the `updating-project-docs` skill:
- `docs/architecture/modules/assault.md` / `global.md` / `open_space.md`;
- `docs/architecture/PROJECT.md` → Conventions: the mine family, mine hostility, launch-scoped hazard registration, the mine footprint, placed mines, the boost-disruption
  and EMP hooks;
- `docs/enemy-roster.md` (Mine Layer, `WaveBuilder.mine_layer()`);
- `ENEMY.md` (Mine Layer);
- `HAZARD.md` (minefield; the mine family's own notes in `enemy_ordnance/`);
- `CLAUDE.md`'s gate list (the new test files) and its projectile convention line ("persistent enemy ordnance ...": mines);
- `tests/README.md` → Gate time (the Phase 7 table).

Close the phase:
- the epic dossier `docs/epics-done/cmug23omu000lm52wu7rak0q5/` (PRD / SOURCES / REPORT). `SOURCES.md` states "internal precedents and measurements only; no external
  research" and points at §2.18, rather than reconstructing sources;
- `## Phase 7 - as built` in `DECISIONS.md`.

## 3. Build sequence

Tasks that edit the same files are chained, because CLAUDE.md allows no worktrees. The mine-variant tasks share `enemy_mine.gd`, `enemy_mine_scenes.gd`,
`test_enemy_mines.gd` and `test_enemy_bullet_lifetime.gd`. The Mine Layer tasks share `mine_layer_brain.gd` and `test_mine_layer.gd`.

| Key | Task | Depends on | Sections |
|---|---|---|---|
| t1 | Recover ≥ 12 s of gate time | — | 2.17 |
| t2 | Mine family core: `EnemyMine`, PROXIMITY = the Bomber's mine, hazard footprint, hostility, placed mode, `EnemyMineScenes` | t1 | 2.1, 2.2, 2.3, 2.17 |
| t3 | Drifting and homing mines | t2 | 2.1, 2.2, 2.4, 2.17 |
| t4 | Chain mine and propagation | t3 | 2.1, 2.2, 2.5, 2.17 |
| t5 | Boost-disruption hook on both players (boost, Boost Drive, dash, warp, boost bar) | t1 | 2.6, 2.17 |
| t6 | Pulse mine | t4, t5 | 2.1, 2.2, 2.6, 2.7, 2.17 |
| t7 | EMP hook stub + EMP mine | t6 | 2.1, 2.2, 2.6, 2.8, 2.17 |
| t8 | Minefield structure (placeholder beacon) | t7 | 2.1, 2.3, 2.4, 2.10, 2.17 |
| t9 | Mine art + minefield beacon art | t8 | 2.1, 2.9, 2.10, 2.17 |
| t10 | Mine Layer shell (needs the HOMING, CHAIN and PULSE scenes) | t6 | 2.1, 2.2, 2.11, 2.17 |
| t11 | Mine Layer passes | t10 | 2.1, 2.3, 2.11, 2.12, 2.17 |
| t12 | Mine Layer hub idle + Open Space persistence | t11 | 2.11, 2.12, 2.14, 2.17 |
| t13 | Mine Layer art, hatch, wake | t12 | 2.11, 2.12, 2.13, 2.17 |
| t14 | Hub placement (patrol + minefield) | t12, t8 | 2.10, 2.11, 2.14, 2.15, 2.17 |
| t15 | Level 1 placement | t13 | 2.11, 2.12, 2.16, 2.17 |
| t16 | Docs, dossier, as-built (medium) | t9, t13, t14, t15 | 1.1, 1.2, 1.3, 2.18, 2.19, 5, 6, 7 |

What can run side by side: t5 with t2–t4, t10 (after t6) with t7–t9, and t14 with t13. Everything else is serial. t10 waits for t6 because its pools and rows use the
HOMING (t3), CHAIN (t4) and PULSE (t6) scenes; t6 already follows t3 and t4, so t11, which needs t10 only, keeps the same critical path.

## 4. Test plan

Each design section carries its own test rows. This index is what the phase adds, and what must stay green.

**New files:**
- `tests/integration/test_enemy_mines.gd` (t2–t4, t6, t7, t9): dual-mode trigger, warning, avoidance, blast, chain, pulse, EMP and art rows;
- `tests/integration/test_player_boost_disruption.gd` (t5, t7): both real players;
- `tests/unit/test_emp_pulse.gd` (t7);
- `tests/integration/test_minefield.gd` (t8);
- `tests/integration/test_mine_layer.gd` (t10–t13, t15).

**Extended:**
- `test_enemy_dual_mode.gd` (Mine Layer cases);
- `test_enemy_bullet_lifetime.gd` (per-variant rows);
- `test_hazards.gd` (field registration);
- `test_sector_hub_patrol.gd` (`_patrol_groups()` + `_element_radius()`), `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd`;
- the four roster files (`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_wreck.gd`'s `_SHIP_SCENES`), `test_hazard_art.gd`.

**§40 coverage, mines in both modes:**
- each mine type's trigger (2.2, 2.4, 2.5, 2.7, 2.8, 2.10);
- chain propagation (2.5);
- boost-disruption application (2.6, 2.7, both real players);
- trail placement (2.12, both harnesses, corridor-relative in Assault).

**Boundary cases:**
- trigger at radius ± margin;
- the warning rule's synthetic failure and the round-1 homing speed 75;
- homing notice 250 / 270 px;
- `chain_radius` 149 / 151 px;
- a non-CHAIN mine stops the chain;
- the efficiency floor 0.15 (strength 0.9 refused, with no tank spent);
- EMP radius ± 1;
- pulse radius 170 / 180;
- live cap 18 → the 19th retires the oldest;
- an ALL mine not set off by non-ship 512 areas;
- avoidance against the `registers_hazard = false` control;
- the Assault budget expiring mid-LAY;
- an arrival at the run-in point perpendicular to the line (LAY still sideways from S on);
- the spread fallback (no legal candidate) and the Open Space approach give-up (layer behind a 220 px/s player), each with its control;
- a hand-placed (AUTHORED) mine authored with the wrong `placed` / hostility (the ready-order row);
- the disruption floors (Boost Drive tail 452 ≥ 420, dash 248 ≥ 180);
- an extra Mine Layer at the peak;
- a Mine Layer in an `ENEMIES_CLEARED` section.

**Must stay green unchanged:**
- every Ph4 Bomber / ordnance row;
- the Ph6 pass-through rows (bit-identical with no hazard in reach) and every `test_context_avoidance.gd` row;
- the level-1 replays and exit guards (or a pre-approved lever from §2.1, reported);
- `test_signal_emit_arity.gd`, `test_enemy_mover_single_writer.gd`;
- `test_resource_uid_integrity.gd`, `test_project_load_integrity.gd`, `scripts/check-test-leaks.sh`;
- every existing Open Space boost and Boost Drive row (`test_open_space_*`), including the module-precedence and check-before-spend rows.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Gate time: 216 s of 240 s before this phase | t1 frees ≥ 12 s first, as a hard floor; per-task allotments (§2.17); hand-ticked rows by default; shared scenarios |
| Bomber mines as hazards (footprint 140) shift a level-1 timing gate: a wall of mines is routed round the long way (§2.3) | Pre-approved levers on `mine.tscn` only: `hazard_pad = 0`, then `registers_hazard = false`; reported, no bound moved |
| A ship whose target is behind a mine line slides along it for seconds | That is Ph6's designed behaviour (measured 14.8 s for a 1400 px trip). Open Space has no deadline; Assault budgets still expire; the level-1 gates catch any stall |
| Many live mines make hazard queries slower (`Hazards.around` / `accel_at` / `penalty_at` iterate every node) | Caps: 18 per Open Space layer, 8 Assault, 9 per placed field. ~45 nodes × ~15 enemies ≈ 2 k cheap checks per tick. t14 measures a hub frame and reports it |
| A pooled mine registering in `_enter_tree()` would plant phantom hazards | Launch-scoped registration, with its own row |
| An ALL mine set off by non-ship 512 areas | The `get_parent()` in `enemies` filter, plus a boundary row |
| Chain loops or double detonation | `_chained` / `_done` latches; the `expired`-once row |
| A disrupted press wasting a boost tank | The efficiency check runs before `try_spend_tank()`; "no tank spent" rows for the Shift boost and the Boost Drive |
| Disrupted boost slower than cruise | The Shift boost and the Boost Drive scale only their excess over `cruise_speed()`, the dash only its excess over `DashState.move_speed`; rows pin 852 / 452 / 248 px/s |
| A layer behind a fast player never reaches its run-in point | Open Space approach give-up after 6 s (fence plan, frozen at once); a player above ≈ 220 px/s is let go by `lose_radius` on purpose |
| A side-on arrival lays a crooked line | The 150 px run-in R → S before LAY; the perpendicular-arrival rows |
| Mine lines unfair at speed | Warning rule ≥ 440 + own speed for every scene; homing outrunnable at 60 px/s; pulse never touches cruise; none of it play-tested (stated) |
| The EMP stand-in reads as a bug ("my boost stopped") | Visible blue-white crackle plus a violet boost-bar tint; owner question 2; Ph9 replaces it |
| Level-1 spill-over: mines persisting into cloud_descent | Placement at 16.0 / 47.0 s; the spill-over row counts `assault_mine_life` |
| The layer's own avoidance pushes it off its line in LAY | "Stays on its path" row; pre-approved lever: drive LAY through `boost()` |

## 6. Out of scope

| Item | Why | Owner |
|---|---|---|
| EMP on enemies, the real EMP player effect, jammers, the hijack pulse | Electronic warfare | Ph9 (keeps the `EmpPulse.emit` / `apply_emp` signatures) |
| Placed minefields in Assault levels | Ph6 deferred placed Assault hazards | Ph15 (the scene already works in the Assault harness) |
| Encounter compositions ("sniper ambush" with a Mine Layer, §19) | Encounter director | Ph13 / Ph14 |
| Mine counts, warning times and cap by difficulty | Difficulty tiers | Ph16 (levers: `mines_per_pass`, `max_live_mines`, `pass_period_*`, the scenes' `warning_time`) |
| Mine / layer audio | No enemy SFX pipeline | Ph17 |
| Merging the race-track mine | Racers are excluded from the rework | not planned (S8) |
| A Mine Layer scattering mines on death | Not asked for; Ph6 leaves the deferred-spawn entry ready | owner option |
| Enemies' boost disrupted by pulse mines | Enemy-laid mines never trigger on enemies; placed ones blast only | Ph9 (if wanted) |
| Mines bending in gravity fields | Ph6 decided mines fly true (distance caps hold) | — |
| Taking the station's reinforcements / `level_2_waves.gd` off rails | Rails | Ph15 (the rail fallback is the contract) |

## 7. Requirements coverage

| Requirement (source) | Delivered by |
|---|---|
| §6.3 Mine Layer role, 80–112 px size | t10 (shell, r 40 body, ≈ 96 px art), t13 |
| §6.3 flies sideways across the encounter, curved or zig-zag trail | t11 (axis ⟂ player frame, ARC / ZIGZAG on vertices) |
| §6.3 mine kinds: proximity, slow homing, chain, pulse (boost efficiency) | t2, t3, t4, t5 + t6 |
| §6.3 build unsafe regions gradually, never fill the screen | t11 (one line per ≈ 10–14 s, ≤ 6 mines, separation, cap) |
| §6.3 Open Space: leave the field, return later and it is still dangerous | t12 (persistence row), t2 (`mine_life` 0) |
| Epic: reuse Ph4 intercept-point selection | t11 (the undamped wall-lead rule on the layer timeline, `TargetInfo`) |
| Epic: Assault clamped to the corridor | t11 (horizontal axis, view-rect clamp, corridor constraint) |
| Epic: added to existing Assault waves | t15 |
| Epic: added to the hub's ambient spawn | t14 |
| Epic: owns its sprite, trail and mine art | t9, t13 |
| §6.9 Mine / Minefield: proximity, drifting, chain, EMP, boost-disruption | t2, t3, t4, t6, t7 |
| §6.9 / §18.6 mines placed as environment structures, not invisible colliders; standalone mines | t8 (Minefield + beacon), t2 (`placed` mode), t14 (hub field) |
| Epic: EMP mine uses the Ph9 EMP hook, may be a stub | t7 (`EmpPulse`, `apply_emp` stand-in) |
| Epic: Ph4 `persist_after_owner_death` lifetime rules | t10 (pools), t2 (one-owner rows) |
| Epic: Ph5 explosion radius | t2 (`ContactBlast` / `pulse_damage` with `blast_radius`, the warning rule) |
| Epic: enemies avoid mines through Ph6 hazard perception | t2 (registration + measured footprint + rows), t8, t11 |
| §11.4 Mine: persistent obstacle | t2, t8, t12 |
| §11.4 Gravity Field | already built in Ph6 (S5) |
| §11.4 EMP Pulse | Ph9; the hook only here (t7) |
| §11.4 Debris Charge | already built in Ph6 |
| §16 explosive collision profile (Ph1 coverage table → Ph7) | already built in Ph2 (`ContactProfile.Mode.EXPLOSIVE`, S6) |
| §21 readability (silhouette, faction accents, gameplay lights), §22 sprite sizes | t9, t13 |
| §23 visual state change | t13 (dispenser hatch), t4 (fuse links), t9 (warning / effect rings) |
| §40 mine tests in both modes: trigger, chain, boost disruption, trail placement | t2–t8, t11 (dual-mode rows; §4) |
| §3.2.5 / §18.6 "hazards affect enemies by their physical rules" | t8 (placed fields hurt enemies; owner question 1) |
| §43 checklist: the player approaches from behind | t11 (tail drop) |
| Ph4 deferral: reconcile the race mine | decided not to merge (S8) |
| Ph6 instruction: start by recovering gate time | t1 |
| Docs | t16 |
| §19 sniper-ambush composition | later phase 13 / 14 |
| Difficulty scaling of mines | later phase 16 |
| Mine audio | later phase 17 |
