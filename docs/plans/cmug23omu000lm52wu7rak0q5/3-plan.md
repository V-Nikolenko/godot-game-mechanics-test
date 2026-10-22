# Enemy rework, phase 7: mines, minefields and the Mine Layer

## Summary for the owner

- **For the player:** a new enemy, the Mine Layer, flies sideways across the fight and leaves a curved or zig-zag line of mines in your path. It lays one line at a time, every few seconds, so danger builds up gradually. In Open Space its mines stay where they were laid: if you fly away and come back, the minefield is still there. In Assault it crosses the screen once ahead of you and leaves.
- **Six kinds of mine**, each with its own shape and light: proximity (explodes when you get close), drifting (moves slowly), slow homing (creeps toward you once it notices you), chain (sets off nearby mines; shooting one sets off the whole linked group), pulse (a small blast that weakens your boost/dash for 2.5 s) and EMP (knocks your boost/dash out for 2 s).
- **The Bomber's existing mine becomes the proximity mine** of this family. Its numbers stay the same and it gets the new art.
- **Enemies see mines as hazards** and steer around them, using the hazard sense built in phase 6.
- **Minefields as places:** a minefield can be placed in a level as a visible structure with a warning beacon. The hub gets one, next to the phase-6 battleground. A placed minefield is dangerous to everyone, so you can lure enemies into it.
- **Where it appears:** one Mine Layer in the hub's ambient patrol, and one each in level 1's Deep Space and Planet Approach sections. Neither section waits for its enemies to be cleared before the level moves on.
- **Built:** the mine family, a boost-weakening hook on both player ships, a placeholder EMP hook for phase 9 to finish, the minefield structure, the Mine Layer (AI, art, hub and level placement), and tests in both game modes.
- **Left out:** EMP effects on enemies and the real EMP effect on the player (phase 9). Placed minefields in Assault levels (phase 15; the scene already works in Assault). Mine counts by difficulty (phase 16). Sound (phase 17). The race track's own mine stays as it is.
- **Main risks:** (1) The tests are near their 240 s time limit (216 s now), so the first task must win back time, and every task has a time allowance. (2) Making the Bomber's mines visible to enemy steering could shift a level-1 timing test. A fallback is already approved. (3) None of this has been play-tested: whether mine lines can be dodged by feel is a judgement call.
- **Choices for you (default in brackets):**
  1. Should a *placed* minefield also hurt and be set off by enemies, while mines an enemy lays hurt only you? [Yes]
  2. Until phase 9 builds the real EMP, should the EMP mine's effect be "boost and dash unavailable for 2 s"? [Yes]
  3. Should the Mine Layer replace its oldest mine once it has 18 alive in Open Space (8 in Assault), rather than stop laying? [Replace the oldest]
  4. Should shooting a chain mine set it off (and its linked neighbours) rather than defuse it like the other mines? [Set it off]
  5. Should the race track's mine stay separate from this family? [Yes, racers are outside the rework]

## For every task

Phase 7 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`) stand unless a line below changes them.
- **Mine family = `EnemyMine extends EnemyOrdnance`**, `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`,
  `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }` (append-only). Scenes `mines/<variant>_mine.tscn`, except PROXIMITY, which **is**
  the existing `enemy_ordnance/mine.tscn` (keeps its path and UID; its script is switched to `EnemyMine`, `kind = MINE`, `variant = PROXIMITY`).
  `EnemyMineScenes` (`mines/enemy_mine_scenes.gd`): `scene_for(variant)`, `pool_size_for(variant, cfg)`. The `EnemyOrdnance`
  contract is unchanged: `signal expired` once per life, `reset()`, `launch(dir, speed, target_point)`. A mine never frees itself. It is never in group `enemies` and never scored.
- **Hostility:** `enum Hostility { PLAYER, ALL }`. PLAYER (default; every mine an enemy lays) is set off only by layer-128 hurtboxes and blasts
  through `ContactBlast` (Ph4, unchanged). ALL (placed minefields only) is also set off by the hurtbox of a node in group `enemies`, and blasts
  through `Hazards.pulse_damage(tree, at, blast_radius, blast_damage)`. That follows the Ph6 rule that environmental blasts hurt both sides.
- **A mine is a hazard:** `hazard_info()` returns one `HazardInfo` updated in place (`kind = &"mine"`, `radius = trigger_radius`,
  `avoid_weight` 0.5 for PLAYER / 0.9 for ALL, `velocity` for moving mines, `source = self`, no pull, no slow, no LOS block). **Pooled hazards register on `launch()`**
  and unregister in `_mark_done()` and in `_exit_tree()`. This deviates from Ph6's register-in-`_enter_tree()`, because a pooled mine sits idle in the tree.
  A mine never writes a ship's velocity, position or rotation.
- **`mine_life` 0 means "never fizzles"**. The `ProjectileLifetime` `max_time` is the backstop (0 = inert). `retire()` = fizzle (fade, no blast, `expired`).
- **Warning rule (Ph4/Ph5):** for every mine scene and every dropper config, `(trigger_radius + effect_radius) / warning_time >= 440` px/s, where
  the effect radius is `blast_radius`, or `pulse_radius` / `emp_radius` for PULSE / EMP. A homing mine adds its own `home_speed` to the 440.
- **Chain:** a CHAIN mine's detonation calls `chain_trigger(chain_delay)` on every live mine whose centre lies within `chain_radius` (found through
  `Hazards.around()`, kind `&"mine"`). A chained mine skips its warning, and only CHAIN mines propagate further.
- **Player hooks (on `PlayerBase`, implemented by both ships):** `apply_boost_disruption(strength: float, seconds: float)`, `boost_efficiency() -> float`,
  `signal boost_disruption_changed(efficiency: float)`. The strongest disruption wins and the longest remaining time wins; they never stack. Below `MIN_BOOST_EFFICIENCY` 0.15 the
  boost and dash refuse to start. `apply_emp(seconds: float, source: Node)`, `is_emp_disrupted()`, `signal emp_changed(active: bool)`. Phase 7's stand-in
  effect is `apply_boost_disruption(1.0, seconds)`, and Ph9 replaces it. **`EmpPulse.emit(tree, at, radius, seconds, source) -> int`**
  (`global/components/emp_pulse.gd`, static) is the one EMP entry point, the "same hook" Ph9's EMP Pulse uses. In Ph7 it reaches only group `player`.
- **Mine Layer** `assault/scenes/enemies/mine_layer/`: `MineLayer extends BaseEnemy`, `MineLayerBrain extends EnemyBrain`, flat `MineLayerConfig`
  (`.tres` wins). `MineLayerBrain.Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only.
  `MineLayer.drop_mine(variant, rest_point) -> EnemyMine` is the only place a layer configures a mine (the `Bomber.drop()` precedent).
  The pools are root `BulletPool` children with `persist_after_owner_death = true`. `WaveBuilder.MINE_LAYER` + `mine_layer()`. `ContactProfile` mode COLLISION.
- **Minefield** `assault/scenes/hazards/minefield/` (`Minefield extends Node2D`, `HAZARD.md`): placed mines are unpooled, `hostility = ALL`, `mine_life` 0,
  `expired -> queue_free`. Works in both modes. In Assault it drifts down at 60 px/s, as wrecks do.
- **Where things live:** mines a layer or Bomber drops live in the enemy container (the pool's container, Ph4). Placed fields are scene children.
  The layer's wake trail lives in the layer's parent container. No mine layer, Bomber, or anything dropping persistent mines goes in an `ENEMIES_CLEARED` section.
- **Conventions kept:** brains tick on physics through the mover (single writer), and gate "stopped" checks on `own_velocity()`. Clocks are accumulated delta, with no `Timer`
  and no `create_timer`. Randomness comes only from `brain.rng`. `accepts_tow()` is false in LAY. Facing follows `sprite_forward_angle` (layer art nose-down, the default `PI/2`).
  Signals are declared with their arity. Per-frame prints sit behind `OS.is_stdout_verbose()`. Art comes only from PixelLab under the `pixel-art-generation` skill and is saved through
  `scripts/pixellab.sh`. Never hand-type a `uid://`. Every task appends its "built in tN" notes to the Phase 7 section of `DECISIONS.md`.
- **Tests:** GUT, written first. Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`). Parameterise on a label string, never
  `use_parameters([HARNESS.open_space(), ...])`. Rows that await real physics run on the **8× clock** (`_scale_clock()` / `_restore_clock()` from
  `test_level1_drone_exit.gd`). A scenario several rows share is computed once. Run `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget.** Measure GUT with `scripts/gate-time.sh` before and after the task, and report both numbers in the task report and in `tests/README.md` → Gate time.
  Allotments are in §2.15. GUT must stay ≤ 240 s, and an over-allotment is fixed by sharing work, never by cutting an assertion.
- **Pass-through stays bit-identical:** with no hazard in reach, enemy velocity and rotation equal Ph6's. The Ph6 pass-through rows stay green.
- Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

## 1. Problem

Today the Bomber can lay a short-lived chain of one kind of proximity mine. Nothing else in the game denies an area over time, and
nothing makes the player remember where danger is. The idea (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`
§6.3, §6.9, §11.4, §18.6, §21–23, §40) asks for:

- a shared mine family with distinct behaviours;
- a Mine Layer that builds unsafe regions gradually (in Open Space they persist, so a place the player returns to is still dangerous);
- minefields placed as visible structures;
- enemies that avoid mines through the phase-6 hazard sense;
- readable art;
- tests in both modes.

### 1.1 Scope check (re-validated against the code on `agent/auto-dev` @ `534bc73`)

The research stage of this epic left no `1-context.md` / `2-research.md` in `docs/plans/cmug23omu000lm52wu7rak0q5/`, so this plan re-read
the code and the decision log itself. Findings that change the phase's scope:

| # | Finding | Effect on scope |
|---|---|---|
| S1 | `EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`) already has `Kind.MINE`: an eject that stops on a rest point, a polled proximity trigger, a warning time, a `ContactBlast`, a shot that defuses it, `mine_life` with a fizzle, and a `ProjectileLifetime` backstop. Ph4 said "Ph7's Mine Layer and mine variants should extend this family". | The proximity variant is the existing mine. Phase 7 adds five variants on the same contract and moves mine-only logic into a subclass. |
| S2 | `BulletPool.persist_after_owner_death` exists (Ph4). `Bomber.drop()` is the single configuring call. | The Mine Layer copies the Bomber's pool shape. No new lifetime rule is needed. |
| S3 | The epic text says mines "use phase 5's explosion radius". Phase 5's rockets blast through `ContactBlast` with a `blast_radius`, and the warhead keeps the Ph4 rule `(trigger + blast) / warning ≥ 420`. Phase 6 added `Hazards.pulse_damage` for environmental blasts that hurt both sides. | PLAYER-hostile mines use `ContactBlast`. ALL-hostile (placed) mines use `pulse_damage`. The warning rule uses 440 (the Bomber's mine band; it is ≥ 420). |
| S4 | Mines are not hazards today. `HazardInfo` names `&"mine"` as a planned kind (Ph6 "Ph7 mines join the same registry with no change to the AI"). The context-avoidance stage already handles any `HazardInfo` with an `avoid_weight`. | Registration only: no AI change. Pooled mines register on `launch()` (deviation from Ph6's `_enter_tree()` rule, stated). |
| S5 | §11.4 Gravity Field was moved to Ph6 and is built (`assault/scenes/hazards/gravity_field/`). | Not in this phase. |
| S6 | The §16 "Explosive collision" contact profile (assigned to Ph7 by Ph1's coverage table) is built: `ContactProfile.Mode.EXPLOSIVE` (Ph2 Swarm Drone). | Nothing to build. Recorded as already delivered. |
| S7 | No player-side hook for "boost efficiency" or EMP exists. The Open Space boost is `OpenSpacePlayerShip._step_boost()` (`boost_exit_speed`) plus the Boost Drive module (`engine_boost_module.gd`, `_BOOST_SPEED`). The Assault equivalent is `DashState.dash_speed`. `EMPBlastModule` is the *player's* EMP against enemies. | Build a `PlayerBase` disruption hook used by both ships, and an EMP entry point, `EmpPulse`, with a stand-in player effect. The EMP effect on enemies is Ph9. |
| S8 | Ph4 deferred "reconciling the race-mode mine (`assault/scenes/race/track/mine.gd`, group `mines`)" to Ph7. Racers are excluded from the rework (`ENEMIES.md`). | Decided: not merged. The race mine stays a race-track prop. Recorded as a decision. |
| S9 | Ph6 leaves gate time at **216.3 s** of the 240 s ceiling and says "Ph7 must start by recovering gate time". | First task: gate-time recovery. Every task gets an allotment (§2.15). |
| S10 | Ph6 placed hazards only in the hub and deferred placed Assault hazards to Ph15. | Minefields are placed in the hub. The scene is proven in the Assault harness but not placed in a level. |
| S11 | Level 1 specialists are pinned and counted against frozen constants with a 2.5× gate (`test_level1_specialist_spawns.gd`). Deep Space peaks at 6 of 12.5. Planet Approach peaks at 7 of 7.5, at 98.0 s. A spill-over row keeps persistent ordnance out of the next `ENEMIES_CLEARED` section. | The Mine Layer counts as a specialist. Placement is early in Planet Approach (47.0 s), away from its 98 s peak. |

## 2. Design

### 2.1 The mine family: `EnemyMine`

**File:** `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`, `class_name EnemyMine extends EnemyOrdnance`. One script carries every
variant: `@export var variant: Variant` with `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }` (append-only), plus
`@export var hostility: Hostility` with `enum Hostility { PLAYER, ALL }`, default PLAYER.

**Why a subclass, not more `EnemyOrdnance.Kind` values:** mine behaviour roughly triples (six variants, the hazard registration, chain links,
retire). Bombs share none of it. `EnemyOrdnance` keeps the bombs and the shared contract. It gains three small virtual hooks the subclass
overrides, so the bomb code paths stay byte-identical:
- `_move_mine(delta)`: today's MINE branch of `_move()`;
- `_trigger_seen() -> bool`: today's `_player_in_range()`;
- `_on_detonated()`: called inside `_detonate()` after `_mark_done()`, in place of the hard-coded `ContactBlast` + gravity field.

Alternative rejected: a component per variant (a `MineBehaviour` child node). Six nodes per pooled mine and a second contract buy nothing
over an enum `match` in one ~400-line script.

**What stays as it is (Ph4 contract):**
- `signal expired` fires once per life.
- `reset()` restores the `_authored` exports. The subclass adds its own exports to the list through an overridable `_reset_props()`.
- `launch(dir, speed, target_point)` starts a life.
- A player hit on the `HurtBox` (Health 1) defuses. CHAIN mines are the exception: shot = detonate (owner question 4).
- The trigger is a **poll** of `ProximityArea.get_overlapping_areas()` once armed. Arming counts from launch.

**New shared behaviour:**
- **`mine_life` 0 = never fizzles.** Today the MINE branch fizzles at `_clock >= mine_life`, so the guard becomes `mine_life > 0.0 and ...`.
  The Bomber always sets 8.0, so its behaviour is unchanged.
- **`retire()`** starts the fizzle (`fizzle_time` fade, no blast, then `expired`). Used by the Mine Layer's live cap and by the backstop.
- **Hazard registration.** `hazard_info()` returns one `HazardInfo` (fields in *For every task*). `position` and `velocity` are refreshed on every `_physics_process`.
  - **Pooled mines register on `launch()`**, because a mine sitting idle in a `BulletPool` is in the tree, and registering in `_enter_tree()` would plant phantom hazards at the pool's position.
  - Unregister happens in `_mark_done()` and in `_exit_tree()` (both idempotent; `Hazards.unregister` already tolerates a missing node).
  - Placed mines (§2.8) call `launch()` too, so there is one path.
- **Hostility ALL:**
  - The `ProximityArea` mask becomes `128 | 512`. `_trigger_seen()` accepts a layer-128 area, or a layer-512 area whose owner is in group `enemies`.
    This rejects other ordnance, rocket shoot-down boxes and plates. A plate's owner is `Plates`, whose parent is the enemy: walk up two levels at most.
  - The blast is `Hazards.pulse_damage(get_tree(), global_position, blast_radius, blast_damage)` (centre distance, both sides; bypasses `EnemyShield`;
    a plated Ram deflects it; this is Ph6's rule).
  - PLAYER mines keep `ContactBlast.spawn(get_parent(), ...)`.
- **Look:** `_draw()` keeps only the state overlay (armed blink, warning blink, blast ring) on top of a `Sprite2D` child named `Sprite`. The
  `body_color` circle is drawn only when the scene has no `Sprite` texture, which is the case until the art task (§2.7).

**The Bomber after this task:** `mine.tscn`'s script becomes `enemy_mine.gd` (`kind = 1`, `variant = PROXIMITY`). `EnemyOrdnanceScenes.MINE` still points at it, and `Bomber.drop()` still configures it.
Every `test_bomber.gd` / `test_enemy_ordnance.gd` row stays green unchanged. **The one behaviour change:** Bomber mines are now hazards, so
other enemies steer round them. Pre-approved lever: if a level-1 gate turns red *because of* the registration, `mine.tscn` sets
`registers_hazard = false` (a new export, default true). The task reports it; no gate bound moves.

**`EnemyMineScenes`** (`mines/enemy_mine_scenes.gd`, RefCounted; the `EnemyRocketScenes` shape):
- `scene_for(variant) -> PackedScene`.
- `pool_size_for(variant, cfg) -> int`. For a `MineLayerConfig`:
  - PROXIMITY = `max_live_mines + 2`;
  - every other variant whose weight `w_<variant>` is > 0 = `ceil(max_live_mines × w / Σw) + 2`;
  - a variant whose weight is 0 = 0 (the pool is not built).
- `export_of(variant, property, fallback)` reads a root export through `PackedScene.get_state()` (the Ph5 `export_of` pattern), so tests and gates read numbers from the scenes, never typed copies.

**Ownership:** pooled mines are owned by their pool until the owner dies, then handed over (`expired -> queue_free`). Placed mines are self-owned
from the start. Both obey "exactly one owner".

**Tests (`tests/integration/test_enemy_mines.gd`, new; the shared mine spec file used by §2.2–§2.6 too):**
- PROXIMITY is `mine.tscn`: `EnemyMineScenes.scene_for(PROXIMITY) == EnemyOrdnanceScenes.MINE`, and its script is `EnemyMine`.
- Registration is launch-scoped. A pooled, unlaunched mine is not counted by `Hazards.count()`. After `launch()` it is, with `kind == &"mine"` and
  `radius == trigger_radius`. After detonate, defuse, fizzle or `retire()`, it is not. A freed mine is not (the `_exit_tree()` row).
- Boundary: `mine_life = 0` → still live at 30 s (hand-ticked). `mine_life = 8` → fizzles at 8.0 s ± 1 tick (Ph4 value unchanged).
- Hostility:
  - A PLAYER mine is not set off by a `fixture_enemy` sitting inside the trigger radius (8× real physics).
  - An ALL mine is set off by it, and its blast lowers that enemy's Health and the player stub's.
  - An ALL mine is not set off by another mine, a rocket's shoot-down box or a Ram plate (the boundary row).
- `retire()` gives no blast and exactly one `expired` (signal-count watcher).
- Avoidance: a `fixture_enemy` with `hazard_avoidance` 0.6 heading straight at a launched mine bends round it, and its closest approach is
  > `trigger_radius`. The same run with `registers_hazard = false` passes inside it (the control).
- `test_enemy_bullet_lifetime.gd`: one time-only row per variant scene (its backstop `max_time` ≥ its `mine_life`, or the backstop is
  inert only for placed use: asserted from `EnemyMineScenes.export_of`). Mine speeds never enter `_every_shipped_enemy_bullet_speed()`.
- Every Ph4 Bomber row green unchanged (named in the task report).

### 2.2 Trigger, warning and blast numbers

**Shared numbers.** The default trigger, arm, warning and blast exports for the Mine Layer variants copy the Bomber's shipped mine:
- `trigger_radius` 80;
- `arm_delay` 0.6 (Bomber 0.5; the layer's mine is dropped closer to its own path);
- `warning_time` 0.25;
- `blast_radius` 48;
- `blast_damage` 30.

**Rule, asserted from scene exports and dropper config, never typed numbers:**
`(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`. The terms:
- `effect_radius` is `blast_radius`, or `pulse_radius` (PULSE) / `emp_radius` (EMP);
- `own_speed` is `home_speed` (HOMING) or `drift_speed` (DRIFTING), else 0.

The rule means a player crossing at the top of the Ph4 mine band is still inside the effect when it fires.

**Tests (in `test_enemy_mines.gd`):**
- The inequality row for every variant scene and for `MineLayerConfig`'s overrides.
- A boundary row: a synthetic mine with `warning_time` 0.4 and blast 48 fails it.
- Dual-mode real-physics rows (8×) for PROXIMITY:
  - a stub crossing at 220 px/s through the trigger radius takes the blast;
  - a stub that stops at `trigger_radius + 30` does not.

### 2.3 Drifting and homing mines

**DRIFTING** (`mines/drifting_mine.tscn`, ships no Mine Layer weight by default; placed fields use it):
- After the eject, it moves at `drift_speed` 35 px/s along its launch direction. A placed mine uses its `drift_direction` export, and `Vector2.ZERO` means still.
- It fizzles once it has travelled `drift_max_distance` 1400 px.
- It does **not** bend in fields (`hazard_pull_scale()` 0, as Ph6 decided for mines), so its distance cap holds.
- `HazardInfo.velocity` is its velocity, so the avoidance stage leads it.

**HOMING** ("slow homing", `mines/homing_mine.tscn`):
- Once armed, it notices the player when the player's centre is within `notice_radius` 260 px.
- It then creeps toward `TargetInfo.player(tree).global_position` at `home_speed` 75 px/s, turning at `home_turn_rate` 2.0 rad/s (`Steering.turn_toward`).
- It stops creeping when the player is beyond `home_lose_radius` 380, or when it is `home_max_distance` 900 px from its launch point (it then holds).
- No player → no motion.
- A sensor `Eye` sprite child faces the player while noticing.
- It is outrun by any player above 75 px/s. That is the counterplay, and a test pins it.

**Tests (dual-mode, hand-ticked through `EnemyMine._physics_process`, which is position-only and needs no physics):**
- DRIFTING moves `35 × t` ± 1 px along its direction.
- DRIFTING fizzles at 1400 px.
- Placed DRIFTING with a zero direction is still.
- HOMING does not move before it is armed.
- HOMING does not move with the player at 270 px (the boundary just outside `notice_radius`), and moves toward the player at 250 px.
- HOMING loses a player who retreats at 120 px/s once the gap passes 380.
- HOMING never ends more than 900 px from its launch point.
- HOMING heads toward the live player each tick within the turn cap.
- Assault: a homing mine never leaves `projectile_world_rect` (it holds at its own cap first).

### 2.4 Chain mine and chain propagation

**CHAIN** (`mines/chain_mine.tscn`):
- `chain_radius` 150, `chain_delay` 0.2 s, `shot_detonates` true (shot = detonate, not defuse; owner question 4).
- **Propagation:** when any CHAIN mine detonates (by trigger, by shot or by chain), it calls `chain_trigger(chain_delay)` on every *other* live
  `EnemyMine` whose centre is within `chain_radius`. The mines are found through `Hazards.around(global_position, chain_radius)` filtered to
  `kind == &"mine"` and `source is EnemyMine`, using centre distance.
- **`chain_trigger(delay)`:** ignored if the mine is done or already chained. Otherwise `_chained = true` and the mine detonates when its own
  accumulated clock has advanced `delay` (no warning, armed or not: a chain is physical).
  - A chained non-CHAIN mine runs its own `_on_detonated()` (blast, pulse or EMP) but propagates no further.
  - A chained CHAIN mine propagates. The result is a visible ripple at 0.2 s a hop.
- **Readability:** every CHAIN mine draws a faint dotted "fuse link" (orange, alpha 0.35, width 1) to each mine within `chain_radius`.
  The set is recomputed every 0.5 s on its own clock, not every frame. That way a player can see which mines are linked before shooting one.

**Tests (dual-mode, hand-ticked; the chain is registry-driven, so no physics is needed):**
- Four CHAIN mines 120 px apart in a line, the first set off → detonation times 0, 0.2, 0.4, 0.6 s ± 1 tick.
- A PROXIMITY mine 120 px from the last CHAIN mine detonates at 0.8 s. A PROXIMITY mine 120 px beyond it does not (non-CHAIN stops the chain; boundary).
- A CHAIN mine 151 px away is not reached (the `chain_radius` boundary); one at 149 px is.
- Shooting a CHAIN mine (real physics 8×, a player bullet) detonates it and its neighbours. Shooting a PROXIMITY mine defuses it (no blast, Ph4 row unchanged).
- A mine already done is never re-triggered (each mine emits `expired` exactly once).
- Mixed hostility: a PLAYER CHAIN mine that sets off an ALL mine produces the ALL mine's `pulse_damage` (enemies hurt).
- Fuse links: `link_points()` lists exactly the neighbours within `chain_radius`.

### 2.5 Boost disruption (player hook) and the pulse mine

**Player hook on `PlayerBase`** (`global/entities/player_base.gd`), implemented by both ships:
- `apply_boost_disruption(strength: float, seconds: float) -> void`. `strength` is 0..1. The live strength becomes `max(live, new)` and the
  remaining time `max(live, new)`, so they never stack.
- `boost_efficiency() -> float` = `1 − strength` while active, else 1.0.
- `signal boost_disruption_changed(efficiency: float)`, emitted on start, change and end.
- `MIN_BOOST_EFFICIENCY := 0.15`.
- The clock is accumulated delta in `_step_disruption(delta)`. `OpenSpacePlayerShip._physics_process` and the Assault fighter's `_physics_process` call it
  (no `Timer`: a hand-steppable seam, like `BoostMeter.step()`).

**What efficiency scales.** Read where it is used, never cached; the exports are never written:
- **Open Space Shift boost:** `_step_boost()`'s start and sustain velocity `boost_exit_speed × hazard_speed_factor() × boost_efficiency()`, and the
  ceiling likewise. Below `MIN_BOOST_EFFICIENCY` the boost refuses to start: no velocity write, no drain (the "refuse, don't weaken" shape of
  `BoostMeter`). The meter's drain is unchanged, so a disrupted boost costs as much and buys less. That is the "efficiency".
- **Boost Drive** (`engine_boost_module.gd`): its burst speeds × `player.boost_efficiency()`, and `try_activate` refuses below the floor
  (duck-typed `has_method`, so a ship without the hook is unchanged).
- **Assault dash** (`dash_state.gd`): `dash_speed × efficiency` in `process_physics`, next to the hazard factor. Below the floor the dash
  transition is refused, as a cooldown is.
- Cruise thrust, turning and firing are **never** touched (§6.6's principle: basic movement and primary fire stay).

**Readability:**
- The Open Space `BoostBar` tints violet and flickers while `efficiency < 1`.
- Both ships show a small violet spark ring (a code-built `Line2D` ring, no PNG) for the duration.

**PULSE mine** (`mines/pulse_mine.tscn`):
- Its detonation calls `apply_boost_disruption(disrupt_strength 0.6, disrupt_seconds 2.5)` on every node in group `player` whose centre is within `pulse_radius` 170.
  The helper is `EnemyMine._disrupt_players(radius, strength, seconds)`, which uses the `Hazards.pulse_damage` centre-distance shape and duck-types `has_method`.
- It also deals a small blast: `blast_damage` 8, `blast_radius` 48.
- Look: an expanding violet ring over 0.3 s (a code-built `Line2D`, self-freeing in the parent container).

**Tests:**
- **`tests/integration/test_player_boost_disruption.gd`, new, dual-mode (real `player_ship.tscn` and the Assault fighter, the `test_player_hazards.gd` setup):**
  - default efficiency is 1.0;
  - after `apply_boost_disruption(0.6, 2.5)`, 0.4 until 2.5 s, then 1.0 ± 1 tick;
  - two disruptions → the stronger strength and the longer time, never the product.
  - Open Space: `_step_boost(true, true, dt)` gives speed `boost_exit_speed × 0.4` ± 1 px/s, and the meter drains as undisrupted.
  - Open Space: at strength 0.9 (efficiency 0.1 < 0.15) the boost refuses, with no velocity write and no drain.
  - Assault: a dash's speed is `dash_speed × 0.4`, and at 0.9 the dash is refused.
  - Boost Drive: the burst is scaled.
  - Cruise thrust is unchanged while disrupted (the control).
  - Each player emits the signal with its arity.
- **In `test_enemy_mines.gd`:**
  - a PULSE mine set off with the real player inside 170 px disrupts it;
  - with the player at 180 px it does not (boundary);
  - in both harnesses.

### 2.6 EMP hook stub and the EMP mine

**`EmpPulse`** (`global/components/emp_pulse.gd`, `class_name EmpPulse extends RefCounted`, static):
- `emit(tree: SceneTree, at: Vector2, radius: float, seconds: float, source: Node) -> int`.
- It calls duck-typed `apply_emp(seconds, source)` on every node in group `player` whose centre is within `radius`, and returns how many were reached.
- Phase 9 extends the target set (enemies, the player's automated weapons) and keeps the signature. **It is the one EMP entry point**: Ph9's EMP Pulse
  weapon and any jammer call it.

**On `PlayerBase`:**
- `apply_emp(seconds: float, source: Node) -> void` sets `_emp_left = max(_emp_left, seconds)` (stepped in `_step_disruption(delta)`) and emits `emp_changed(active: bool)` on start and end.
- `is_emp_disrupted() -> bool`.
- **Phase 7's stand-in effect** is `apply_boost_disruption(1.0, seconds)`: boost, Boost Drive and dash are unavailable for the window (owner question 2).
- A comment marks the stand-in body as Ph9's to replace. Ph9 changes the body, not the signature.

**EMP mine** (`mines/emp_mine.tscn`):
- No hull damage: `blast_damage` 0, so no `ContactBlast` is spawned and no `pulse_damage` is dealt.
- Its detonation calls `EmpPulse.emit(get_tree(), global_position, emp_radius 190, emp_seconds 2.0, self)`.
- Look: a blue-white crackle ring over 0.35 s (code-built `Line2D`).
- No Mine Layer weight by default. Placed fields use it.

**Tests:**
- **`tests/unit/test_emp_pulse.gd`, new:**
  - reaches a stub with `apply_emp` inside the radius, not one outside it (boundary at radius ± 1);
  - returns the count;
  - ignores nodes without the method;
  - never touches group `enemies` in Ph7 (a stub enemy with `apply_emp` is not called; this row is Ph9's to flip).
- **`test_player_boost_disruption.gd`:**
  - `apply_emp(2.0, null)` → `is_emp_disrupted()` and `boost_efficiency() == 0.0` for 2.0 s;
  - boost and dash refused;
  - `emp_changed(true)` then `(false)`.
- **`test_enemy_mines.gd`:** an EMP mine set off near the real player in both harnesses reaches it, and deals no Health damage.

### 2.7 Mine art and readability

**Assets.** One PixelLab sprite per variant, under `assault/assets/sprites/projectiles/mines/`:
- `mine_proximity.png`, `mine_drifting.png`, `mine_homing.png` (+ `mine_homing_eye.png`), `mine_chain.png`, `mine_pulse.png`, `mine_emp.png`;
- `minefield_beacon.png` (warning buoy, ≈ 24 × 32).

**Generation rules:**
- 24 × 24 px source, **strict top-down** (`view: "high top-down"`, `isometric: false`).
- Visual check on every image. Saved through `scripts/pixellab.sh`.
- Each sprite keeps a transparent margin, so `test_entity_sprite_transparency.gd` (≤ 90 % opaque) passes. The Ph4 plate lesson: draw by script if a generated sprite has a painted-in glow.

**Readability rules (IDEAS §21–23):**
- **Faction palette:** dark hull, cool dark-blue edge light, one red faction mark.
- **One silhouette per variant:**
  - proximity: round, spiked;
  - drifting: round, two fins and a tiny nozzle;
  - homing: a single sensor lens;
  - chain: hexagonal, three linked prongs;
  - pulse: coil ring around a violet core;
  - EMP: a small dish/antenna, blue-white core.
- **Gameplay light drawn on top, never painted in:**
  - red slow blink = armed;
  - yellow fast blink + blast ring = warning;
  - violet (pulse) / blue-white (EMP) ring = effect radius shown during the warning;
  - chain fuse links (§2.4).
- The Bomber's mine (PROXIMITY) gets the proximity sprite: one family, one look.

**Scene changes:**
- Each mine scene gains a `Sprite` (`Sprite2D`) child. `_draw()` stops drawing the body circle when `Sprite.texture` is set.
- `body_color` is removed from the mine scenes, as Ph5 did for rockets (look-only).

**Tests:**
- `test_enemy_mines.gd`: every variant scene has an opaque `Sprite` at its centre (the Ph5 rocket art row shape).
- The transparency sweep green.
- `test_hazard_art.gd` gains the beacon.

### 2.8 Minefields as structures

**`Minefield`** (`assault/scenes/hazards/minefield/minefield.gd` + `minefield.tscn`, `class_name Minefield extends Node2D`, with `HAZARD.md`): a visible
placed structure, never an invisible collider.

**Exports:**
- `pattern: Pattern { AUTHORED, RING, GRID, SCATTER }`.
- `count` 9, `radius` 200, `spacing` 110, `rng_seed` (0 = fixed 1).
- Flat weights `w_proximity` 1.0, `w_drifting`, `w_homing`, `w_chain`, `w_pulse`, `w_emp` (all 0 by default).
- `hostility` (default `ALL`; owner question 1).
- `drift_direction` for DRIFTING mines.
- `assault_drift_speed` 60.

**Building the field:**
- AUTHORED uses the `EnemyMine` children placed in the editor under `Mines`.
- RING / GRID / SCATTER instance mine scenes from `EnemyMineScenes` into `Mines` in `_ready()`. This is load-time, not inside a physics flush. A runtime spawn uses `spawn_into(container, at)`, the Ph6 deferred entry.
- **Every placed mine:**
  - `hostility` = the field's;
  - `mine_life` 0;
  - its `ProjectileLifetime.max_time` 0 (inert);
  - `expired -> queue_free`;
  - `launch(Vector2.ZERO, 0.0, global_position)` (registers it as a hazard).

**Beacon:** a `Beacon` `Sprite2D` (the minefield beacon art) with an amber `StateLight`-style blink marks the field. It goes dark when the last mine is gone. The field node frees itself one second later.

**Modes:**
- In Open Space the field is still.
- In Assault (an `assault_arena` provider exists) the field node moves itself down at `assault_drift_speed`. This is the wreck precedent and stands in for scrolling: a mine's own position writes are local. The field frees itself once it is below `EnemyWorld.projectile_world_rect(tree)`, or after 40 s.
- No level-1 placement (Ph15 places Assault hazards).

**Tests (`tests/integration/test_minefield.gd`, new; dual-mode where marked):**
- RING with `count` 9 lays 9 mines on a 200 px circle (± 0.5 px).
- GRID spacing.
- SCATTER is seed-stable: the same seed gives the same points, and a different seed gives different ones.
- AUTHORED keeps the editor positions.
- Every placed mine is ALL, never fizzles (60 s hand-ticked) and is registered.
- The field frees after its last mine.
- **Both modes:** a player stub driven through the field is set off by a mine. An enemy fixture with `hazard_avoidance` 0 driven through it is set off and damaged. A fixture with `hazard_avoidance` 0.6 routes round it with no detonation.
- **Assault:** the field moves `60 × t` down, frees past the world rect, and its mines' `HazardInfo.position` follows.
- `test_hazards.gd`: a field adds `count` to `Hazards.count()` and removes them when it is freed.

### 2.9 Mine Layer shell

**Files** (`assault/scenes/enemies/mine_layer/`):
- `mine_layer.tscn`, `mine_layer.gd` (`MineLayer extends BaseEnemy`), `mine_layer_brain.gd`;
- `mine_layer_config.gd/.tres` (`MineLayerConfig extends ShipConfig`, flat, `@export_group`s);
- `ENEMY.md`.

**Scene:**
- Body `CircleShape2D` r 40, shared by the body, the root `HurtBox` (hurtbox ≤ body, the Ph6 rule) and the `ContactHitBox` (mask 128).
- Size class 80–112 px: the art is ≈ 96 px.
- A `Dispenser` `Marker2D` at the stern, local (0, −38); nose-down art, so +y is forward.
- A `StateLight`.
- `EnemyMover` + `MineLayerBrain`.
- `ContactProfile` mode COLLISION (`collision_damage` 25).
- One root `BulletPool` per variant with weight > 0 (`ProximityPool`, `ChainPool`, `PulsePool`, `HomingPool`, and `DriftingPool` / `EmpPool` only if their weights are raised), each `persist_after_owner_death = true`, sized in the scene and gated equal to `EnemyMineScenes.pool_size_for()`.
- Placeholder hull art until §2.11 (`bomber.png` scaled).

**`MineLayerConfig` (flat; `.tres` values; the brain task fills the rest of its groups):**
- **Scoring / Defense:** `max_health` 140, `collision_damage` 25, `score_value` 60.
- **Movement:** `max_speed` 240, `acceleration` 420, `max_turn_rate` 2.4, `lay_speed` 170, `exit_speed` 300.
- **Hazards:** `hazard_avoidance` 0.6, `hazard_margin` 24, `hazard_resistance` 0.2. Wreck: `wreck_chance` 0.35, `wreck_size` medium, `explosive_wreck_chance` 0.
- **Mines:**
  - `trigger_radius` 80, `mine_arm_delay` 0.6, `mine_warning` 0.25, `mine_blast_radius` 48, `mine_blast_damage` 30;
  - `mine_eject_speed` 120, `mine_eject_time` 0.3;
  - `assault_mine_life` 9.0, `open_space_mine_life` 0.0 (persists), `open_space_mine_backstop` 240.0;
  - `max_live_mines` 18, `assault_max_live_mines` 8;
  - `w_proximity` 0.5, `w_chain` 0.2, `w_pulse` 0.15, `w_homing` 0.15, `w_drifting` 0.0, `w_emp` 0.0.
- **Engagement:** `engage_seconds` 9.0 (Assault budget).
- **Rail:** `rail_mine_interval` 1.6.

**`MineLayer.drop_mine(variant, rest_point) -> EnemyMine`:**
- Acquires from the variant's pool at `Dispenser`, falling back to `ProximityPool` when that pool is absent or exhausted.
- Applies the config's mine numbers. `mine_life` / backstop are chosen per mode: Assault when `EnemyWorld.arena(tree)` exists.
- Launches it toward `rest_point` at `2·|rest − pos| / mine_eject_time`, so it stops on the point (the Bomber's eject rule, within 4 px).
- Returns null if nothing was acquired.

**Brain shell:**
- `Phase` declared in full (*For every task*). This task plays only APPROACH (seek the player at `max_speed`) and DISENGAGE (exit at `exit_speed` along the current heading, the Bomber's exit).
- `start_engaged` seam.
- `accepts_tow()` refuses in LAY.

**Rail fallback** (mandatory, the Ph3/Ph4 rule): `on_suspended()` starts a `_process` clock on `MineLayer` that drops a PROXIMITY mine at the `Dispenser` (speed 0) every `rail_mine_interval`, life `assault_mine_life`.

**Roster gates:** add the scene to the hand-maintained rosters (`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`). `test_config_instance_isolation.gd`'s sweep and the wreck rule "no hurtbox larger than its body" (`test_wreck.gd`) pick it up.

**Tests (`tests/integration/test_mine_layer.gd`, new):**
- Pool sizes equal `pool_size_for`.
- `drop_mine` configures every field from the config in each mode: Assault life 9.0, Open Space life 0 with backstop 240.
- The eject stops within 4 px of the rest point.
- An exhausted CHAIN pool falls back to PROXIMITY.
- The pools hand over on the layer's death: a mine laid before death still triggers after it.
- The rail fallback drops at 1.6 s ± 1 tick on a real `EnemyPathMover`.
- `accepts_tow()` is false in LAY.
- The case in `test_enemy_dual_mode.gd` (shell: APPROACH closes on the player in both modes, inside the corridor in Assault).

### 2.10 Mine Layer passes (the combat AI)

**What it does:** the layer flies *sideways across* the player's path, laying one curved or zig-zag line of mines per pass. Then it breaks off,
waits at a standoff, and lays the next line somewhere else. Danger builds gradually: one line every 6–9 s, never the whole screen.

**Player frame:**
- P = the player's position.
- v̄ = smoothed velocity: an exponential average, `velocity_smoothing` 0.5 s, the Bomber's `smoothed_velocity()` shape.
- f = v̄ / |v̄| when |v̄| ≥ `frame_speed` 60, else the unit vector from P toward the layer.

**Pass plan (`plan_pass()`, re-planned every tick in APPROACH until frozen):**
- **Lead (the Ph4 wall rule, undamped, on the layer's own timeline):** `t_lead = min(t_arrive + (L/2) / lay_speed + mine_arm_delay, lead_horizon)`, where:
  - `t_arrive = |S − pos| / max_speed`;
  - `L` = `pass_length` 720 (Assault `assault_pass_length` 560);
  - `lead_horizon` 3.0.
- **Centre C:**
  - moving player: `P + v̄·t_lead + f·ahead_distance` (260);
  - standing player: `P + f·fence_distance` (320). The fence goes between the player and the layer.
- **Axis:** `u = f.orthogonal()`, signed so that S, the start end, is the end nearer the layer. `S = C − u·L/2`, `E = C + u·L/2`.
- **Shape:** ZIGZAG (vertices every `zigzag_wavelength / 2` = 120 px, offset ±`zigzag_amplitude` 70 along f) or ARC (a quadratic bow of `arc_depth`
  130 toward P). The choice is drawn from `brain.rng` with `arc_chance` 0.5, once per pass.
- **Mine rest points:** every `mine_spacing` 120 px of path length from S, at most `mines_per_pass` 6.
  - Open Space only: a rest point within `trigger_radius + 40` of a live mine is skipped (no stacking).
  - Variant per mine from the flat weights by `rng`, at most one HOMING per pass.
- **Spread:** in Open Space a new C must be ≥ `min_pass_separation` 380 px from the centre of every earlier pass that still has a live mine.
  If it is not, C is rotated about P in ±40° steps, up to 4. If none is legal, the plan proceeds; this is logged behind `is_stdout_verbose`.
- **Assault ("clamped to the corridor"):**
  - u is forced horizontal (±x), with S on the side the layer is on.
  - C.y = P.y − `assault_ahead` 220.
  - C, S and E are clamped into `EnemyWorld.view_rect(tree).grow(−(view_margin 64 + zigzag_amplitude))`, so every mine lands where the player can be.
  - The `AssaultCorridorConstraint` still filters the flight.

**Phases:**
- **APPROACH:** seek S at `max_speed`. The plan is frozen once within `commit_distance` 200 px of S, then LAY. In Assault, budget expiry in APPROACH → DISENGAGE.
- **LAY** (committed; `accepts_tow()` false):
  - Pure pursuit along the polyline (a point `path_lookahead` 60 px ahead) at `lay_speed`.
  - Each mine is dropped when the layer's arc length passes its rest point minus the eject lead (`mine_eject_speed × mine_eject_time / 2`, the Bomber's rule), through `drop_mine`.
  - The `StateLight` goes CHARGING for 0.3 s before each drop, and the dispenser hatch is open for the whole of LAY (§2.11).
  - Whatever was not dropped by the end goes at the end, so a pass always delivers its pattern.
  - Stall guard: `L·1.2 / lay_speed + 0.5` s.
  - The Assault budget defers to the end of LAY. A telegraphed attack is never cut off; the deferral bound is that stall guard, ≤ 4.45 s.
- **BREAK_OFF:** `mover.break_contact(P, v̄, side, break_speed 260)` for `break_seconds` 1.2. `side` points away from the fresh line.
  Assault: DISENGAGE instead (one pass per life).
- **REPOSITION** (Open Space): orbit P at `standoff_range` 600, direction drawn per pass, for a period drawn from `pass_period_min..max` 5.0–7.0 s. Then APPROACH.
- **DISENGAGE:** continue along u (sideways, off the far side) at `exit_speed`.
- **Tail drop (any engaged phase except LAY):** if the player is within `tail_range` 280 and inside the rear `tail_cone_deg` 60° cone, drop one
  PROXIMITY mine at the Dispenser with no eject, at most every `tail_drop_cooldown` 2.5 s. Chasing a Mine Layer is dangerous.
- **Live cap:** the brain keeps a FIFO of live mines (instance ids; dead ones are pruned). Before a drop at `max_live_mines` (Assault `assault_max_live_mines`), it
  `retire()`s the oldest (owner question 3). Handed-over mines of a dead layer are no longer counted by anyone.

**Config fields this task adds:**
- `velocity_smoothing`, `frame_speed`;
- `pass_length`, `assault_pass_length`, `mine_spacing`, `mines_per_pass`;
- `zigzag_amplitude`, `zigzag_wavelength`, `arc_depth`, `arc_chance`;
- `ahead_distance`, `fence_distance`, `assault_ahead`, `lead_horizon`;
- `commit_distance`, `path_lookahead`, `min_pass_separation`;
- `break_speed`, `break_seconds`, `standoff_range`, `pass_period_min`, `pass_period_max`;
- `tail_range`, `tail_cone_deg`, `tail_drop_cooldown`, `view_margin`.

**Test seams:** `pass_centre`, `pass_start`, `pass_end`, `pass_shape`, `planned_rest_points`, `drops_this_pass`, `passes_started`, `live_mine_count()`, `smoothed_velocity()`, `plan_pass()`.

**Tests (`test_mine_layer.gd` + cases in `test_enemy_dual_mode.gd`; hand-ticked with `_tick()`, the shared scenario computed once in `before_all`):**
- **Trail placement, both modes:**
  - ZIGZAG rest points alternate sides of the axis by 70 ± 4 px.
  - ARC points bow toward P (all on P's side, max offset 130 ± 6).
  - Spacing is 120 ± 4 px.
  - Every mine ends within 4 px of its planned point.
  - In Assault every mine lies inside `view_rect().grow(−64)`, and the axis is horizontal (|u.y| < 0.01).
- **Lead:**
  - for a stub moving at 220 px/s, C lies ahead of the live player's position at the moment the middle mine arms (projection on v̄ > 0);
  - for a standing stub, C is between it and the layer;
  - for a stub reversing at LAY start, the line is still where it was planned (frozen).
- **Sideways:** during LAY, the layer's velocity is within 35° of u (it crosses the player's path, not toward it).
- **Gradual:**
  - Open Space over 30 s: passes are ≥ 5 s apart;
  - each pass ≤ 6 mines;
  - no two pass centres closer than 380 px while both have live mines;
  - the live count never exceeds 18 (the 19th drop retires the oldest; boundary).
- **Assault:**
  - exactly one pass per life, then DISENGAGE sideways;
  - with the budget expiring mid-LAY, the pass completes (all 6 mines dropped) within the stall guard.
- **Tail drop:**
  - a stub 200 px behind in the cone gets a mine within one tick, and no second one before 2.5 s;
  - a stub 200 px *in front* gets none (the control).
- `accepts_tow()` false in LAY, true in REPOSITION.
- **Hazard-aware:** a second pass routes round the first pass's mines. Its closest approach to every live mine is > `trigger_radius`, which is its own avoidance.

### 2.11 Mine Layer art, dispenser state and wake trail

**Hull:** `assault/assets/sprites/enemies/mine_layer.png`, a PixelLab `create_map_object`:
- strict top-down (`high top-down`, `isometric: false`), ≈ 96 × 96;
- nose-down (`sprite_forward_angle` default `PI/2`);
- a wide, flat specialist hull with a visible rear mine rack;
- dark hull, cool edge light, red faction stripe, no painted glows or flames.

Generate several candidates and pick the best (the CLAUDE.md "use PixelLab freely" rule), with a visual check on each.

**Dispenser hatch (§23 "every specialist has a readable state change"):** `mine_layer_hatch.png`, a sprite over the rack.
- Its `scale.y` eases from closed to open over 0.25 s when LAY starts, and closes on leaving LAY.
- `MineLayer.set_hatch_open(0..1)` is driven by the brain. The Godot zero-scale epsilon applies, so tests compare with a tolerance.

**Wake trail:** `MineWake` (`mine_layer/mine_wake.gd`), a code-built `Line2D` added to the layer's parent container at LAY start.
- It appends the `Dispenser`'s global position every 12 px during LAY: width 3, dark-red → transparent gradient, alpha 0.45.
- It fades over `wake_fade` 2.5 s after LAY ends, then frees itself on its own clock. This is the `RailTrail` precedent; it never uses `create_timer`.
- It shows where the line of mines was just laid.

**Tests (`test_mine_layer.gd`):**
- The hull sprite is opaque at the centre and transparent at the corners.
- The hatch is closed outside LAY and open during it.
- The wake has ≥ 2 points per 24 px laid, lies within 4 px of the layer's dispenser path, and is freed 2.5 s ± 1 tick after LAY ends.
- The transparency sweep is green.

### 2.12 Mine Layer hub idle and Open Space persistence

**Idle:** the Ph4/Ph5 template.
- `AnchorIdle` runs ahead of the phase dispatch: `patrol_anchor` (default = spawn), `idle_phase_offset` from `rng`, `start_engaged`.
- IDLE / NOTICING / RETURNING are appended, and their values are fixed by the enum in *For every task*.
- Assault builds no `AnchorIdle`. `on_suspended()` drops it.
- **Not interruptible by RETURNING:** LAY. The return is retried every tick.
- NOTICING redraws the pass period, so a layer that idled for a minute does not lay the instant it notices.
- Idle never lays and never tail-drops.

**Idle config group:**
- `perceive_radius` 650, `lose_radius` 1500, `notice_time` 0.35, `idle_radius` 160, `idle_speed` 0.5.
- **Inequality asserted from the config:** `lose_radius > standoff_range + break_speed × break_seconds + pass_length / 2`, i.e. 600 + 312 + 360 = 1272 < 1500. The layer's own cycle never sends it home mid-fight.

**Open Space persistence ("an area the player comes back to stays dangerous"):**
- Mines laid in Open Space have `mine_life` 0 and a backstop of 240 s.
- RETURNING does not touch them, and the layer's death hands them over.

**Tests (`test_mine_layer.gd`, Open Space harness):**
- The inequality row.
- Frame-0 IDLE.
- NOTICING after `notice_time` inside `perceive_radius`.
- RETURNING beyond `lose_radius`, but not during LAY.
- **The persistence row (hand-ticked, one shared scenario):**
  - the layer lays a pass;
  - the player stub flies 1600 px away and the layer returns home;
  - 60 s of game time later the player stub flies back through the line;
  - every mine is still at its rest point, still registered, and the first one it reaches sets it off.
- The same row in Assault shows the mines gone after `assault_mine_life` (the mode difference, asserted).

### 2.13 Hub placement: Mine Layer patrol and a placed minefield

**Patrol spawn:**
- `SectorHub._spawn_patrol()` appends `_spawn_mine_layer(_mine_layer_anchor(), rng)` **after** the existing 14 draws (draw 15). Every earlier seed is unchanged.
- New exports `mine_layer_ring_radius` 2600 and `mine_layer_anchor_bearing_deg` 0, giving the anchor (2600, 0): between the hub and the Ph6 `TacticalSpace`, about 900 px from its structures.
- `patrol_anchor` and a nonzero `rng_seed` are set before `add_child()`.

**Placed minefield:**
- `TacticalSpace/Minefield` at (3300, 560), north of the well-anomaly lane.
- RING, `count` 9, `radius` 200, weights `w_proximity` 0.4 / `w_chain` 0.3 / `w_drifting` 0.15 / `w_emp` 0.15, `hostility` ALL, `rng_seed` 7.
- It is a lure: the player can pull patrols into it, and the well's pull toward it is part of the place.

**Clearance (`test_sector_hub_patrol.gd`):**
- **Mine Layer ring:** a row asserting the anchor clears every `MissionTrigger` / `PickupBase` and the player spawn by `idle_radius + perceive_radius`, with the margin printed.
- **Anchor spacing:** the nine anchors stay more than 1000 px apart. The Mine Layer's nearest is the Gatling's at (1500, 0), 1100 px away.
- **Minefield:** a new row asserting it clears every interactable and the spawn by ≥ `radius + trigger_radius + 400`, and every patrol anchor's idle ring by ≥ 200 px.
- The seed row, the container count and the frame-0 IDLE list gain the layer.
- A hub Mine Layer's mine lands in `EnemyContainer` (8×).

If a clearance row fails, the bearing / ring / field position moves (exports). No other group moves.

### 2.14 Level 1 placement

**Placement:** two Mine Layer lines, each **inside an existing wave of a DURATION section** (no new wave, so no other wave's effective trigger moves; read the
Phase 3 "wave-order quirk"):
- `deep_space` wave 16.0 s: `b.mine_layer().at(-400, -160)`, entering from the left;
- `planet_approach` wave 47.0 s: `b.mine_layer().at(400, -160)`, entering from the right.

Both AI spawns: no `.move()`, no `.free_after()`. Never in an `ENEMIES_CLEARED` section (mines persist).

**Gates:**
- **`test_level1_specialist_spawns.gd`:** an `EXPECTED_PH7` pin (2 rows) and a row-count sanity check. The Mine Layer counts as a specialist in the frozen
  2.5× count gate. Its life is `engage_seconds + lay deferral (stall guard) + 2 ticks + measured exit`, with the exit from
  `SpecialistExitProbe.worst_disengage()` over `corridor_starts()` at `[exit_speed, 10]`, measured once in `before_all`.
  - Spill-over row: the life plus `assault_mine_life` must end before cloud_descent's last trigger. The mines count, as a corvette's rocket life does.
  - Boundary: an extra Mine Layer at planet_approach's measured peak fails the gate.
- **`test_engagement_deadline.gd`:** a "no `ENEMIES_CLEARED` section contains a Mine Layer" row, plus a boundary row: a Mine Layer added to cloud_descent's last wave computes over the timeout.
- **Attack-in-budget row (`test_mine_layer.gd`):** from each of the two level-1 spawns, through a real `WaveManager`
  (`tests/helpers/level1_slice_replay.gd`, window `rel − 1 s .. rel + engage + 5 s`, 8×), the layer reaches LAY before its budget expires, lays
  ≥ 4 mines inside `view_rect()`, and does one pass per life.

If a gate fails, the task moves its own line's offset or wave (within the same section), or escalates. No lever on another enemy is pre-approved.

### 2.15 Gate time

Phase 6 ended at **GUT 216.3 s** (wall 221.4 s) of the 240 s ceiling. The slowest files are `test_fighter_squad.gd` 64.2 s, `test_level1_fighter_fire_density.gd` 32.4 s,
`test_level1_specialist_exit.gd` 10.1 s, `test_bomber.gd` 8.7 s and `test_enemy_ordnance.gd` 7.7 s.

**t1 (gate room) must free ≥ 12 s (target GUT ≤ 204 s) and never below 8 s.** It uses only the `tests/README.md` → Gate time rules:
- 8× clock for any row still awaiting real physics at 1× (check Ph6's `test_wreck*.gd`, `test_hazard_projectiles.gd`, `test_player_hazards.gd`, `test_bomber.gd`);
- compute a shared scenario once;
- drop per-tick bookkeeping;
- or a behaviour-identical speed-up of a hot production path. For example, the fighter tick that `test_fighter_squad.gd`'s 168-layout sweep spends 53 s in (~290 µs per four-fighter tick). Proof: identical outputs on the existing rows.

It never lowers a tick count, duration, sample count or grid, never widens a bound, and never removes an assertion.

**Allotments (new GUT seconds; total 28.0 s):**

| Task | t2 | t3 | t4 | t5 | t6 | t7 | t8 | t9 | t10 | t11 | t12 | t13 | t14 | t15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Allotment (s) | 3.0 | 1.5 | 1.5 | 2.0 | 1.0 | 0.5 | 1.5 | 1.5 | 4.0 | 0.5 | 1.5 | 1.5 | 8.0 | 0 |

So the phase ends ≤ 232 s (≤ 236 s if t1 frees only 8 s).

**Costs:** a real-physics case at 8× costs ≈ 0.25–0.4 s, a hand-ticked dual-mode case ≈ 0.02–0.06 s, and a slice replay at 8× ≈ 2–5 s.

### 2.16 Docs

Run the `updating-project-docs` skill:
- `docs/architecture/modules/assault.md` / `global.md` / `open_space.md`;
- `docs/architecture/PROJECT.md` → Conventions: the mine family, mine hostility, launch-scoped hazard registration, the boost-disruption and EMP hooks;
- `docs/enemy-roster.md` (Mine Layer, `WaveBuilder.mine_layer()`);
- `ENEMY.md` (Mine Layer);
- `HAZARD.md` (minefield; the mine family's own notes in `enemy_ordnance/`);
- `CLAUDE.md`'s gate list (the new test files) and its projectile convention line ("persistent enemy ordnance ...": mines);
- `tests/README.md` → Gate time (the Phase 7 table).

Close the phase:
- the epic dossier `docs/epics-done/cmug23omu000lm52wu7rak0q5/` (PRD / SOURCES / REPORT);
- `## Phase 7 - as built` in `DECISIONS.md`.

## 3. Build sequence

| Key | Task | Depends on | Sections |
|---|---|---|---|
| t1 | Recover gate time | — | 2.15 |
| t2 | Mine family core (`EnemyMine`, PROXIMITY = the Bomber's mine, hazard registration, hostility, `EnemyMineScenes`) | t1 | 2.1, 2.2, 2.15 |
| t3 | Drifting and homing mines | t2 | 2.1, 2.2, 2.3 |
| t4 | Chain mine and propagation | t2 | 2.1, 2.2, 2.4 |
| t5 | Boost disruption hook on both players + pulse mine | t2 | 2.1, 2.2, 2.5 |
| t6 | EMP hook stub + EMP mine | t5 | 2.1, 2.5, 2.6 |
| t7 | Mine and beacon art | t3, t4, t5, t6 | 2.1, 2.7, 2.8, 2.15 |
| t8 | Minefield structure | t4 | 2.1, 2.8 |
| t9 | Mine Layer shell | t2 | 2.1, 2.9 |
| t10 | Mine Layer passes | t9, t3, t4, t5 | 2.1, 2.9, 2.10 |
| t11 | Mine Layer art, hatch, wake | t10 | 2.9, 2.10, 2.11 |
| t12 | Mine Layer hub idle + Open Space persistence | t10 | 2.9, 2.10, 2.12 |
| t13 | Hub placement (patrol + minefield) | t12, t8 | 2.8, 2.12, 2.13 |
| t14 | Level 1 placement | t10 | 2.9, 2.10, 2.14 |
| t15 | Docs, dossier, as-built | t7, t11, t13, t14 | 2.16, 1.1, 5, 6, 7 |

t3/t4/t5/t9 can run in parallel after t2; t8 after t4; t11/t12/t14 in parallel after t10.

## 4. Test plan

Each design section above carries its own test rows. This index is what the phase adds, and what must stay green.

**New files:**
- `tests/integration/test_enemy_mines.gd` (t2–t7; dual-mode trigger, warning, blast, chain, pulse, EMP, art rows);
- `tests/integration/test_player_boost_disruption.gd` (t5, t6; both real players);
- `tests/unit/test_emp_pulse.gd` (t6);
- `tests/integration/test_minefield.gd` (t8);
- `tests/integration/test_mine_layer.gd` (t9–t12, t14).

**Extended:**
- `test_enemy_dual_mode.gd` (Mine Layer cases);
- `test_enemy_bullet_lifetime.gd` (per-variant rows);
- `test_hazards.gd` (field registration);
- `test_sector_hub_patrol.gd`, `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd`;
- the three roster files, `test_hazard_art.gd`.

**§40 coverage, mines in both modes:**
- each mine type's trigger (2.2, 2.3, 2.4, 2.5, 2.6, 2.8);
- chain propagation (2.4);
- boost-disruption application (2.5, both real players);
- trail placement (2.10, both harnesses, corridor-relative in Assault).

**Boundary cases:**
- trigger at radius ± margin;
- homing notice 250 / 270 px;
- `chain_radius` 149 / 151 px;
- a non-CHAIN mine stops the chain;
- the efficiency floor 0.15 (strength 0.9 refused);
- EMP radius ± 1;
- live cap 18 → the 19th retires the oldest;
- the warning-rule synthetic failure;
- an ALL mine is not set off by non-ship 512 areas;
- Assault budget expiring mid-LAY;
- an extra Mine Layer at the peak;
- a Mine Layer in an `ENEMIES_CLEARED` section.

**Must stay green unchanged:**
- every Ph4 Bomber / ordnance row;
- the Ph6 pass-through rows (bit-identical with no hazard in reach);
- the level-1 replays and exit guards;
- `test_signal_emit_arity.gd`, `test_enemy_mover_single_writer.gd`;
- `test_resource_uid_integrity.gd`, `test_project_load_integrity.gd`, `scripts/check-test-leaks.sh`.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Gate time: 216 s of 240 s before this phase | t1 recovers ≥ 12 s first; per-task allotments (§2.15); hand-ticked rows by default; shared scenarios |
| Registering the Bomber's mines as hazards shifts a level-1 timing gate (enemies now steer round them in planet_approach) | Pre-approved lever: `registers_hazard = false` on `mine.tscn` only; reported, no bound moved |
| Many live mines make the hazard queries slower (`Hazards.around` / `accel_at` / `penalty_at` iterate every node) | Caps: 18 per Open Space layer, 8 Assault, 9 per placed field. ~45 nodes × ~15 enemies is ≈ 2 k cheap checks per tick. t13 measures a hub frame and reports it |
| A pooled mine registering in `_enter_tree()` would plant phantom hazards | Launch-scoped registration (§2.1), with its own test row |
| An ALL mine set off by non-ship 512 areas (ordnance, rocket boxes, plates) | Owner-in-`enemies` filter plus a boundary row |
| Chain loops or double detonation | `_chained` / `_done` latches; the `expired`-once row |
| Mine lines unfair at speed | Warning rule ≥ 440 + own speed; homing outrunnable at 75 px/s; pulse never touches cruise; none of it play-tested (stated) |
| The EMP stand-in reads as a bug ("my boost stopped") | Visible blue-white crackle plus a violet boost-bar tint; owner question 2; Ph9 replaces it |
| Level-1 spill-over: mines persisting into cloud_descent | Placement at 16.0 / 47.0 s; the spill-over row counts `assault_mine_life` |

## 6. Out of scope

| Item | Why | Owner |
|---|---|---|
| EMP on enemies, the real EMP player effect, jammers, the hijack pulse | Electronic warfare | Ph9 (keeps `EmpPulse.emit` / `apply_emp` signatures) |
| Placed minefields in Assault levels | Ph6 deferred placed Assault hazards | Ph15 (the scene already works in the Assault harness) |
| Encounter compositions ("sniper ambush" with a Mine Layer, §19) | Encounter director | Ph13 / Ph14 |
| Mine counts, warning times and cap by difficulty | Difficulty tiers | Ph16 (levers: `mines_per_pass`, `max_live_mines`, `pass_period_*`, `mine_warning`) |
| Mine / layer audio | No enemy SFX pipeline | Ph17 |
| Merging the race-track mine | Racers are excluded from the rework | not planned (decision S8) |
| A Mine Layer scattering mines on death | Not asked for; Ph6 leaves the deferred-spawn entry ready | owner option |
| Enemies' boost being disrupted by pulse mines | Enemy-laid mines never trigger on enemies; placed ones blast only | Ph9 (if wanted) |
| Mines bending in gravity fields | Ph6 decided mines fly true (distance caps hold) | — |
| Taking the station's reinforcements / `level_2_waves.gd` off rails | Rails | Ph15 (the rail fallback is the contract) |

## 7. Requirements coverage

| Requirement (source) | Delivered by |
|---|---|
| §6.3 Mine Layer role, 80–112 px size | t9 (shell, r 40 body, ≈ 96 px art), t11 |
| §6.3 flies sideways across the encounter, curved or zig-zag trail | t10 (axis ⟂ player frame, ARC / ZIGZAG) |
| §6.3 mine kinds: proximity, slow homing, chain, pulse (boost efficiency) | t2, t3, t4, t5 |
| §6.3 build unsafe regions gradually, never fill the screen | t10 (one line per 6–9 s, ≤ 6 mines, separation, cap) |
| §6.3 Open Space: leave the field, return later and it is still dangerous | t12 (persistence row), t2 (`mine_life` 0) |
| Epic: reuse Ph4 intercept-point selection | t10 (the undamped wall-lead rule on the layer timeline, `TargetInfo.predicted_position`) |
| Epic: Assault clamped to the corridor | t10 (horizontal axis, view-rect clamp, corridor constraint) |
| Epic: added to existing Assault waves | t14 |
| Epic: added to the hub's ambient spawn | t13 |
| Epic: owns its sprite, trail and mine art | t7, t11 |
| §6.9 Mine / Minefield: proximity, drifting, chain, EMP, boost-disruption | t2, t3, t4, t5, t6 |
| §6.9 / §18.6 mines placed as environment structures, not invisible colliders | t8 (Minefield + beacon), t13 (hub field) |
| Epic: EMP mine uses the Ph9 EMP hook, may be a stub | t6 (`EmpPulse`, `apply_emp` stand-in) |
| Epic: Ph4 `persist_after_owner_death` lifetime rules | t9 (pools), t2 (one-owner rows) |
| Epic: Ph5 explosion radius | t2 (`ContactBlast` / `pulse_damage` with `blast_radius`), t2 (warning rule) |
| Epic: enemies avoid mines through Ph6 hazard perception | t2 (registration + avoidance row), t8, t10 |
| §11.4 Mine: persistent obstacle | t2, t8, t12 |
| §11.4 Gravity Field | already built in Ph6 (S5) |
| §11.4 EMP Pulse | Ph9; the hook only here (t6) |
| §11.4 Debris Charge | already built in Ph6 |
| §16 explosive collision profile (Ph1 coverage table L11 → Ph7) | already built in Ph2 (`ContactProfile.Mode.EXPLOSIVE`, S6) |
| §21 readability (silhouette, faction accents, gameplay lights), §22 sprite sizes | t7, t11 |
| §23 visual state change | t11 (dispenser hatch), t4 (fuse links), t7 (warning / effect rings) |
| §40 mine tests in both modes: trigger, chain, boost disruption, trail placement | t2–t6, t8, t10 (dual-mode rows; §4) |
| §3.2.5 / §18.6 "hazards affect enemies by their physical rules" | t8 (placed fields hurt enemies; owner question 1) |
| §43 checklist: the player approaches from behind | t10 (tail drop) |
| Ph4 deferral: reconcile the race mine | decided not to merge (S8) |
| Ph6 instruction: start by recovering gate time | t1 |
| Docs | t15 |
| §19 sniper-ambush composition | later phase 13 / 14 |
| Difficulty scaling of mines | later phase 16 |
| Mine audio | later phase 17 |
