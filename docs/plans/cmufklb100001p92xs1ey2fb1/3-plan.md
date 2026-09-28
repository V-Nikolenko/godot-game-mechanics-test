# Enemy rework, phase 1: a mode-neutral enemy AI architecture, and the plan for the full roster

Epic `cmufklb100001p92xs1ey2fb1` · plan task `cmufklb4p000bp92xhnbr13y6` · written 2026-09-25 against
`agent/auto-dev` @ `3df6e1e`; **revision 2** (2026-09-25, @ `a6c2cff`) answers the plan review in `4-review.md`
(F1–F11). Every change is listed in §10 *Response to feedback*.

Built on `1-context.md` (codebase facts, requirements R1–R14 / L1–L21) and `2-research.md` (outside findings,
improvements I-1…I-17). Neither is re-derived here. The attached documents live in
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/` (`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` = **[IDEAS]**, `ENEMIES.md` =
**[AUDIT]**, the same text as `docs/enemy-rework/current-enemies.md`). This is phase 1 of 19. No earlier phase
exists, so there is no *as built* section to build on yet. `DECISIONS.md` is created by this run.

Spot-checked in the code for this plan: `base_enemy.gd` (mask at 51, flip at 70–73, `print` at 82),
`enemy_path_mover.gd` (62–65 suspension by node name), `drone_interceptor.gd` (whole file), `attack_controller.gd`,
`aimed_attack_pattern.gd`, `enemy_bullet.gd` (bounds at 12–16), `bullet_pool.gd` (`acquire` sets the position
and *then* calls `reset()`, 62–76), `project.godot [layer_names]` (171–179).

---

## 0. Proposed changes to the owner's ideas (read these first)

The owner asked for every change to their ideas to sit at the top. Each item below is a change to
`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` with its reason. Items marked ✱ were already accepted by the epic's
Phase 1 scope text; the rest are new.

| # | Change to the ideas | Why |
|---|---|---|
| **P-1** ✱ | The movement contract is called **`EnemyMover`**, not `MovementController`. | `class_name MovementController` is already the player's input handler (`assault/scenes/player/movement_controller.gd:1`), so reusing the name will not compile. |
| **P-2** ✱ | **Extend the existing `AttackController`** (`global/components/attack_controller.gd`). Do not add a second one. | It already *is* the §3.1 contract: a pattern plus a pool on a timer. Two enemies (`light_assault_ship.gd:39`, `interceptor.gd:36`) and the ally fighter (`ally_fighter.gd:40-46`, with a `ForwardAttackPattern`) use it. It needs three additions: an aim source (TargetInfo plus accuracy), a hold-fire switch the brain drives, and `fire_now()` for telegraphed shots. |
| **P-3** ✱ | §30's `MovementProfile` / `AttackProfile` / `DefenseProfile` / `TacticalProfile` become **`@export_group` sections of flat fields on each enemy's `ShipConfig` subclass**. They are not nested resources. | `test_config_instance_isolation.gd` rejects any Object/Array/Dictionary field on a config (209–227) and allows one `*config*.tres` per entity dir (107). Groups give the same at-a-glance inspector. The data stays a complete shallow copy for `privatise()`. |
| **P-4** ✱ | **`DefenseProfile` is a scene component node**, not a `Resource`. It owns the hurtbox mask and `accepted_damage_types`. Runtime armour state lives on the node. | A mutable shared resource would leak the ram ship's "armour stripped" state to every ram ship. That is the exact trap `privatise()` exists for. A node is per-instance by construction. |
| **P-5** | Armour stays a **damage rule on a full-size hurtbox**. Later armour should prefer `accepted_damage_types` plus `is_armored()` deflection over mask exclusion. The ram ship's mask toggle (33 → 97) is kept byte-identical in Phase 1 and becomes profile *data*. | The project already ruled this, and `test_enemy_hurtbox_geometry.gd` gates it. A mask-excluded bullet passes through silently; a deflected one flashes and reports. Phase 4's Ram Corvette decides whether to move to deflection. |
| **P-6** ✱ | "Name every used layer" is **five fixes, not two**: layer 3's typo (`environemnt_player` → `environment_player`), layer 5 `pickups` (all 12 pickups use it; the audit missed it), layer 6 `player_rockets`, layer 11 `hazard_contact`. **Every numeric value is unchanged.** A `CollisionLayers` constants script replaces magic numbers in the code this phase touches. | Layer names are display-only in Godot, so renaming is safe. Keeping the numbers answers the epic's open question on "numeric layer allocation". IDEAS §15's table is kept except for one entry: it reserves 4096 for bosses. Bosses need no layer, because boss modules are ordinary enemy hurtboxes (the station's turrets prove it). IDEAS' 2048 "area-control / special hazards" is a distinct meaning and is adopted as-is, but no new layer is allocated until something uses it: **Phase 6** allocates `area_control` (2048) when gravity wells arrive. |
| **P-7** ✱ | The Assault constraint is a **velocity filter** between the mover's desired velocity and the single `move_and_slide()`. It has a **soft band** (edge pressure) and a **hard band** (IDEAS §34's 450 px). An enemy outside the hard band may only move *inward* until it has entered. | Every Assault spawn starts above the screen (`wave_manager.gd:175`), so a hard clamp would teleport it. This has the same shape as Godot's `NavigationAgent2D` velocity hook. Nova Drift fixed the same problem by steering fresh enemies on-screen first (`2-research.md` §2). |
| **P-8** ✱ | Phase 1 **ports the Drone Interceptor** onto the new contracts as the proof consumer. Its tuning and identity are kept, and its behaviour spec runs in both modes. To stay **1:1 in Assault** it runs with `constraint_mode = NONE` in Phase 1; the corridor is wired onto it by Phase 2's Razor Drone. | Contracts that nothing real uses drift into the wrong shape. It is the only self-driven, world-pixel enemy with prediction code, and it spawns without `.move()`. Phase 2's Razor Drone *builds on* the port. |
| **P-9** ✱ | Brains **tick on physics through one owner** (`BaseEnemy._physics_process`), with accumulated-`delta` clocks and an injectable seeded `RandomNumberGenerator`. The brain uses no `Timer` nodes. | GUT `simulate()` does not fire Timers. `StateMachine` ticks in `_process`, which is why the path mover has to disable it by name. The race AI already uses the `tick(delta)` shape (`RacerStateMachine`). |
| **P-10** ✱ | `EnemyPathMover` **suspends AI through a `suspend_ai()` contract**, *in addition to* what it does today. `set_physics_process(false)` and the `"AIStateMachine"` name lookup both keep running **unconditionally** — neither is a fallback that `suspend_ai()` can switch off. The name lookup retires in Phase 15, when the light assault ship's state machine moves onto a brain. | A duck-typed call, like `is_armored()` and `face_instant()`. The light assault ship is a `BaseEnemy` (so it will *have* `suspend_ai()`), but its `AIStateMachine` states write `velocity` and call `move_and_slide()` from `_process` (`approach_state.gd:24-25`, `strafe_exit_state.gd:14-15`), which only the name lookup stops. An `if has_method … else <lookup>` would make it fight the rail on most of level 1. While a path is attached, the path mover stays the only position writer, so all 264 path-driven spawns are unchanged. |
| **P-11** ✱ | `TargetInfo`'s intercept **can fail** and returns an `ok` flag. An **`accuracy` 0–1** knob blends intercept aim with direct aim. Assault patterns default to `0.0`, which is today's aim exactly. | A target faster than the shot has no intercept solution. A 100%-accurate AI is not fun. One scalar is the whole hook that Phase 16's difficulty tiers turn. |
| **P-12** ✱ | `ProjectileLifetime` is a component that **emits the host's `expired`** and never frees anything itself. Its rules are `max_time`, `max_distance` from the origin, and an optional `world_rect` supplied by the mode. `persist_after_owner_death` is **documented only** and becomes a pool policy in Phase 5 (rockets). | This keeps the one-owner rule: a pooled bullet recycles, and an unpooled sniper shot frees through its existing `expired → queue_free`. It **arms itself lazily** on its first physics tick (or on `reset()`), because the unpooled sniper shot is never `reset()`. Screen visibility is deliberately not a rule, because it is camera-bound and false on the first frame. IDEAS' `max_distance_from_owner` becomes distance from the *origin* (the owner may be freed or moving; the origin is always valid), and `explicit_destroy()` is `expire_now()` — see §2.9. |
| **P-13** | The mode is **declared by the world, found by duck-type**. `ArenaCamera` joins the group `&"assault_arena"` and answers `projectile_world_rect()`, `enemy_cull_rect()` and (from t11) `enemy_movement_constraint()`. One static helper, `EnemyWorld` (`global/enemy_ai/enemy_world.gd`), is the only code that looks the provider up. With no provider in the tree, the mode is Open Space: no constraint, no rect, no cull. Tests inject all of them directly. | Nothing in `global/` may import the Assault-only `ArenaCamera` class. A group plus `has_method` is the project's accepted cross-module contract. Open Space needs zero wiring, and the same enemy scene runs in both modes. |
| **P-14** | IDEAS §41's seven phases become the **19-phase chain** on the board (§7). The three blocks §41 never slotted are placed explicitly: battlefield structures (§6.3–6.10), hazard perception (§3.2.5), and the art pass (§21–23). Phases 18 and 19 carry the heavy-ship follow-through: Carrier and Heavy Gunship moved onto the boss machinery Phase 11 builds, and hazards / line of sight / wrecks applied to the heavy ships and bosses. | Without a slot they would silently fall out of scope. The board's chain is the source of truth for the count (19 as of this revision; revision 1 said 17 because phases 18–19 were added after it). §7 fills in what each phase inherits from this one. |
| **P-15** ✱ | **`DamageReaction` does not replace BaseEnemy's damage flow in Phase 1.** `_on_received_damage` / `_on_health_changed` become documented virtual hooks instead. The question comes back in Phase 5, when enemies first need shields. | The flows differ: an AnimationPlayer flash versus a tween, no Shield support, and the station's delayed death override. Swapping now is churn across 10 enemies and the boss for no player-visible gain. |
| **P-16** ✱ | PatrolDrone is **characterised, not fixed**. Its rocket immunity (HurtBox mask 64 only) and its body sitting on the `enemy_hitbox` layer are pinned as today's behaviour. Phase 2's Swarm Drone replaces it (IDEAS §2). | Fixing a scrapped enemy is wasted work. The pin makes the replacement's diff visible. |
| **P-17** ✱ | "Same behaviour spec in both modes" gets a concrete form. A shared helper builds an `open_space` harness (no constraint) and an `assault` harness (corridor). Behaviour tests run over both with GUT's `use_parameters`. Assertions are stated *relative to the constraint*. | IDEAS §40 asks for it and gives no mechanism. |
| **P-18** | `BulletPool`'s grandparent container is **not** changed in Phase 1. It moves to **Phase 2**, the first phase that fires enemy weapons in Open Space (the Razor Drone's pulse). | Every current user matches pool → ship → container, including `SectorHub`'s `EnemyContainer`. Phase 1 fires no enemy bullet in Open Space, so changing it now is untested churn. The phase scope text does not list it. |

---

## 1. Problem

**Today, for the player.** In Assault, almost every enemy flies a pre-drawn rail: 264 of 268 shipped spawns use
`.move()`. The rail silently switches off the enemy's own AI, so the Bomber, Kamikaze Drone and others never do
what their docs say. In Open Space the only enemy, the PatrolDrone, drifts in a straight line forever, and the
player's rockets pass straight through it. Nothing about enemy behaviour carries over between the modes: bullets
die at a fixed Assault rectangle, and movement is tied to the Assault camera's scale and screen edges.

**What this phase changes.** Phase 1 is invisible to the player by design, apart from one enemy. It lays the
foundation that phases 2–19 build ~10 reworked enemies, structures and bosses on:

- An enemy can *want* something: a brain.
- An enemy can *get there* in world space: a mover with steering primitives.
- The Assault corridor becomes a *filter* on that movement, not a separate AI.
- Enemy bullets expire by world rules.
- The collision layers have names.
- The hurtbox mask is data.
- There is one way to ask "where is the player, and where will they be".

The Drone Interceptor is rebuilt on all of it, and must play the same in Assault. It also works in Open Space.
Every existing Assault wave plays exactly as today.

---

## 2. Design

### 2.1 Where things live

| New / changed | Path | Kind |
|---|---|---|
| `CollisionLayers` | `global/physics/collision_layers.gd` | constants script (`class_name`, no node) |
| `DefenseProfile` | `global/components/defense_profile.gd` | `Node` component |
| `TargetInfo` | `global/enemy_ai/target_info.gd` | `RefCounted` value + static resolver |
| `Steering` | `global/enemy_ai/steering.gd` | static, stateless primitive functions |
| `EnemyWorld` | `global/enemy_ai/enemy_world.gd` | static helper: the one lookup of the `&"assault_arena"` provider (P-13) |
| `EnemyMover` | `global/enemy_ai/enemy_mover.gd` | `Node` component, the single writer of the actor's `velocity`/`rotation` when active |
| `EnemyBrain` | `global/enemy_ai/enemy_brain.gd` | `Node` base with `tick(delta)`; concrete brains extend it |
| `MovementConstraint` | `global/enemy_ai/movement_constraint.gd` | `RefCounted` base: `filter(position, desired) -> Vector2` (identity) |
| `AssaultCorridorConstraint` | `assault/scenes/systems/assault_corridor_constraint.gd` | extends `MovementConstraint` |
| `ProjectileLifetime` | `global/components/projectile_lifetime.gd` | `Node` component |
| `AttackController` | `global/components/attack_controller.gd` | extended (§2.7) |
| `BaseEnemy` | `assault/scenes/enemies/base_enemy.gd` | refactored in place (it stays where 10 scenes and every test reference it) |
| `ArenaCamera` | `assault/scenes/systems/arena_camera.gd` | joins `&"assault_arena"`; `projectile_world_rect()` + `enemy_cull_rect()` (t4b), `enemy_movement_constraint()` (t11) |
| `DroneInterceptorBrain` | `assault/scenes/enemies/drone_interceptor/drone_interceptor_brain.gd` | the proof consumer |

**Rejected:** moving `BaseEnemy` to `global/` in Phase 1. It is the right end state for a mode-neutral base, but
it means 10 scenes, WaveBuilder and every roster test re-pointing their paths, for no behavioural change. It is
deferred to Phase 15 (Assault migration), when those files are being rewritten anyway.

### 2.2 The tick: one owner, one clock

`BaseEnemy` gains a `_physics_process(delta)` that runs only if the enemy has an `EnemyBrain` child. Children are
resolved *by type* in `_ready()`, following the `ShipTurnController` precedent:

```
if _ai_suspended or _brain == null: return
_brain.tick(delta)          # decides: calls mover/attack request API
_mover.step(delta)          # desired → limits → constraint.filter → velocity → move_and_slide → facing
```

- Subclasses that still define their own `_physics_process` (bomber, gunship, ram, kamikaze) override it and are
  untouched. So they keep today's behaviour with no change.
- `AttackController` keeps its `_process` timer by default. When `driven_by_brain = true`, the brain calls
  `controller.tick(delta)` instead, so fire timing shares the physics clock.
- **Rejected:** reusing `global/statemachine/StateMachine` as the brain. It ticks in `_process` and is
  suspended by magic name. A brain *may* hold `State` children internally, but the outer clock is `tick`.
- **Rejected:** behaviour trees or utility AI. There is no precedent in the project, and IDEAS §4 itself calls
  for 3–5 states per enemy.

### 2.3 `EnemyBrain` contract

```gdscript
class_name EnemyBrain extends Node
var actor: CharacterBody2D            # set by BaseEnemy before the first tick (not typed BaseEnemy: F11)
var mover: EnemyMover                 # sibling, resolved by type; may be null
var attack: AttackController          # sibling, resolved by type; may be null
var rng := RandomNumberGenerator.new()  # randomize()d in _ready unless `rng_seed` export != 0
func tick(_delta: float) -> void: pass  # virtual
func on_suspended() -> void: pass       # virtual
```

- Perception goes through `TargetInfo` only. No brain calls `get_nodes_in_group("player")`.
- States are an `enum` inside the brain for simple enemies, or `State` children for complex ones. This matches
  CLAUDE.md's two styles.
- IDEAS §4's shared state names (SPAWN, SEARCH, APPROACH, POSITION, ATTACK, EVADE, REPOSITION, DISENGAGE,
  PANIC, DESTROYED) are **documented as the vocabulary** in `enemy_brain.gd`'s header. They are not enforced
  as a base enum: each enemy uses 3–5 of them, and a shared enum no single enemy fully uses is noise.
  The ported interceptor maps ENTER→APPROACH, ORBIT→POSITION and DASH→ATTACK in its comments.

### 2.4 `Steering` primitives and `EnemyMover`

`Steering` is a set of **pure static functions**. Each returns a *desired velocity* in world px/s, and each is
unit-tested alone:

| Primitive | Signature (sketch) | Notes |
|---|---|---|
| `seek` | `(pos, target_pos, max_speed)` | full speed toward |
| `arrive` | `(pos, vel, target_pos, max_speed, accel)` | slowing radius **derived** as `v²/(2·accel)`, never a free number (research §2) |
| `orbit` | `(pos, center, radius, angle, max_correct_speed)` → anchor point `center + RIGHT.rotated(angle)·radius`, speed `clamp(dist·4, 60, max_correct_speed)` | this is exactly the interceptor's orbit (`drone_interceptor.gd:95-109`), so the port is exact. The *caller* advances `angle`. |
| `intercept` | `(pos, target: TargetInfo, speed, lookahead)` | Reynolds pursuit, using `target.predicted_position(lookahead)` |
| `evade` / `retreat_from` | `(pos, threat_pos, max_speed)` / with the threat's velocity | `retreat_from` = flee; `evade` = flee from the predicted position |
| `strafe` | `(pos, target_pos, side, max_speed)` | perpendicular to the line to the target; `side` ±1 |
| `hold_position` | `(pos, vel, anchor, tolerance, max_speed, accel)` | `arrive` inside `tolerance` → zero |
| `drift` | `(direction, speed)` | constant; PatrolDrone's model |
| `boost` | stateful, so it lives on `EnemyMover`: `boost(dir, speed, duration)` overrides the desired velocity for `duration` and ignores the accel limit | |

Deferred primitives, each owned by the phase that first needs it:
- `spiral` / `corkscrew` → Phase 2 (swarm)
- `lead_target` → Phase 3 (fighter). It is `TargetInfo.aim_direction`, already here.
- `break_contact` → Phase 4 (sniper)
- `regroup` / `formation_slot` → Phase 2 (squad roles) and Phase 14

`EnemyMover` (`Node`, a child of the enemy) holds the current request. The brain calls **one primary** request
per tick: `mover.request_velocity(v)`, or convenience wrappers such as `mover.orbit(...)` that call `Steering`.
A brain may add an *offered* nudge (`add_nudge(v)`), after `LateralMover`'s "offered, brain opts in".

Weighted blending of several primitives is **rejected**. With few, individually visible enemies, the
cancellation shows as stalls (Fray, research §2). Context steering is the planned upgrade in Phase 6, with
hazards.

`step(delta)` runs:

1. Take the desired velocity.
2. Apply `max_speed` / `acceleration` / `braking` limits. The velocity change per step is capped at
   `acceleration · delta` when speeding up and `braking · delta` when the desired speed is lower than the current
   one (`braking = 0` means "same as `acceleration`"). `acceleration = 0` means instant, which is what the port
   needs to stay exact, since today's interceptor sets velocity directly.
3. `constraint.filter(actor.global_position, v)`, if there is a constraint.
4. `actor.velocity = v; actor.move_and_slide()`.
5. Facing. **One facing rule** for every mover-driven enemy:
   `target = heading.angle() - sprite_forward_angle`, then
   `rotation = lerp_angle(rotation, target, delta · turn_lerp)`, and if `max_turn_rate > 0` the change this step
   is additionally capped at `max_turn_rate · delta` (rad/s — IDEAS §3.1's `turn_rate`).
   `heading` is either the velocity or an explicit `face_toward(point)` request. `turn_lerp = 0` means instant.
   `sprite_forward_angle` is read **duck-typed** (`actor.get("sprite_forward_angle")`, default `PI/2` when
   absent), so nothing in `global/enemy_ai/` is typed against the Assault class `BaseEnemy` (F11). Only
   `BaseEnemy` → `global/` dependencies exist, which is the allowed direction, and Phase 15's move of
   `BaseEnemy` to `global/` needs no change in these files.

`EnemyMover` exports `max_speed`, `acceleration`, `braking`, `turn_lerp`, `max_turn_rate` and `constraint_mode`
(`AUTO` | `NONE`).
- `AUTO` resolves the constraint once in `_ready()` through `EnemyWorld.movement_constraint(tree)` (P-13).
- `NONE` never resolves one. The ported Drone Interceptor uses `NONE` in Phase 1 (§2.11).
- `mover.constraint = X` set before `add_child` wins, which is how tests inject a mode.

**Single-writer gate.** When an `EnemyMover` is present it is the only writer of the actor's `velocity` and
`rotation` and the only caller of `move_and_slide()`. t10 adds `tests/integration/test_enemy_mover_single_writer.gd`,
a source sweep in the style of `test_ship_rotation_single_writer.gd`: every `*_brain.gd` under `assault/` and
`global/`, every script under `global/enemy_ai/` except `enemy_mover.gd`, and the root script of every enemy scene
that contains an `EnemyMover` node, must contain no `velocity =`/`+=`/`-=`, no `rotation =`/`+=`/`-=` and no
`move_and_slide(`. The allowlist is empty and permanent. The fixture covers it from t10; the ported interceptor is
swept automatically from t14.

It never `push_error`s when parented to a non-`CharacterBody2D`. It `push_warning`s and disables itself instead,
because `test_project_load_integrity.gd` instantiates every script with zero engine errors allowed.

### 2.5 `AssaultCorridorConstraint`

```
visible = Rect2 of the Assault playfield, derived from ArenaCamera constants:
          pinned centre (640,360) ± half viewport ± (H_LIMIT, V_LIMIT)  →  x −100…1380, y −380…1100
soft    = visible grown by soft_band (120 px)        # edge pressure ramps 0→1 across this band
hard    = visible grown by hard_band (450 px, IDEAS §34)
```

`filter(pos, v)` works **per axis** (x and y independently, each against its own pair of edges). For one axis,
`d` is how far `pos` lies outside `visible` on that axis (0 inside), and "outward" means the sign pointing
away from `visible` on that axis. All speeds are **px/s**, added to or removed from the velocity component on
that axis.

1. **Not yet entered** (`pos` outside `visible` on either axis, and it has never been fully inside): on each
   axis where `d > 0`, only an inward component is kept; if it is below `entry_speed` (px/s, default 60) it is
   raised to `entry_speed`. Axes where `d = 0` pass through unchanged, so a spawn above the screen keeps its
   lateral motion. `entered` latches true once `pos` is inside `visible`. The hard band does **not** apply
   before the latch: a wave spawn at y ≈ −860 (beyond the −830 hard edge, `wave_manager.gd:175` with
   `offset.y ≈ −380`) enters at its own inward speed, laterally free.
2. **Entered, `0 < d ≤ soft`** (soft band, 120 px): the outward component is kept, and an inward pressure of
   `edge_pressure · d / soft` is added (`edge_pressure`, px/s, default 200). Inside `visible` the pressure is 0.
3. **Entered, `soft < d < hard`** (outer band, 120–450 px): full inward pressure `edge_pressure` is added, and
   the outward component is scaled by `1 − (d − soft) / (hard − soft)`, reaching 0 at `hard`.
4. **Entered, `d ≥ hard`** (450 px, IDEAS §34): the outward component is removed and full `edge_pressure` is
   added. This is what IDEAS §34's **"forced to re-enter"** means here: past the hard edge the net velocity on
   that axis is inward at ≥ `edge_pressure` px/s whatever the brain asks for, until the enemy is back inside
   `hard`; bands 3 → 2 then hand control back smoothly. The tangential axis is untouched, so the enemy slides
   along the edge and never stalls.

One constraint instance per mover. It holds the `entered` latch, so the provider returns a *new* instance each
call. The numbers (120, 450, 60, 200) are judgement or IDEAS §34, and they are flat exports on the constraint.

**Phase 1 consumers.** Only the test fixture (in the dual-mode harness) runs under the corridor in Phase 1. The
ported Drone Interceptor uses `constraint_mode = NONE` (§2.11), because under AUTO it would deviate from today in
two places: orbiting a player clamped to the corridor edge (`player_fighter.gd:99-100` clamps to exactly
`visible`) puts the orbit up to 130 px into the band, where pressure bends it; and nothing in the pins could see
that. Phase 2 (Razor Drone) switches it on deliberately and re-pins.

**Rejected:**
- A position clamp after `move_and_slide`: it teleports spawns and desyncs velocity.
- Transforming the AI into camera space: it reintroduces exactly the coupling the epic removes.

### 2.5a The Assault provider and `EnemyWorld` (one owner: t4b)

`arena_camera.gd` is edited by exactly two tasks, **in sequence** (F5): t4b creates the provider, and t11, which
depends on t4b, adds one method to it. t13 depends on t4b and never edits the file.

- **t4b:** `ArenaCamera._ready()` adds itself to `&"assault_arena"`, and gains
  - `projectile_world_rect() -> Rect2`: the corridor `visible` rect (pinned centre ± half viewport ±
    `H_LIMIT`/`V_LIMIT`, from the class constants) grown by 64 px → x −164…1444, y −444…1164;
  - `enemy_cull_rect() -> Rect2`: `global_position ± visible_rect_size/2 ± 80`, the Drone Interceptor's legacy
    cull, computed from the live viewport as today.
- **t11:** adds `enemy_movement_constraint() -> MovementConstraint` (a new `AssaultCorridorConstraint` per call).
- `EnemyWorld` (`global/enemy_ai/enemy_world.gd`, static, `class_name` checked free) is the only code that looks
  the provider up: `arena(tree) -> Node` (first node in the group, or null), `projectile_world_rect(tree)`,
  `cull_rect(tree)` and `movement_constraint(tree)`. Each returns null / an empty `Rect2` with a `has_*` check
  when there is no provider or the provider lacks the method (duck-typed `has_method`), so t4b's version of
  `movement_constraint()` simply returns null until t11 lands. Nothing under `global/` names `ArenaCamera`.

### 2.6 `TargetInfo`

`class_name TargetInfo extends RefCounted`. It is a snapshot taken at construction, so a target freed mid-frame
cannot crash the reader.

| Member | Meaning |
|---|---|
| `static func player(tree: SceneTree) -> TargetInfo` | **the one player resolver**. It replaces scattered `get_nodes_in_group("player")[0]` calls in the code this phase touches. Returns a TargetInfo with `has_target = false` when there is none. |
| `static func of(node: Node2D) -> TargetInfo` | any node; `velocity` is read if it is a `CharacterBody2D`, else `ZERO` |
| `has_target`, `position`, `velocity`, `facing` (the node's rotation as a unit vector) | snapshot |
| `distance_from(p)`, `relative_angle_from(p, from_facing)` | |
| `predicted_position(t)` | `position + velocity · t` |
| `intercept(from, shot_speed) -> Dictionary {ok, point, time}` | closed-form quadratic. `ok = false` for no positive root, zero `shot_speed`, or no target. `point` then falls back to `position`. |
| `aim_direction(from, shot_speed, accuracy) -> Vector2` | `accuracy` 0 = direct aim at `position` (today); 1 = intercept point; in between = lerp of the two points; a failed intercept falls back to direct. No target → `Vector2.DOWN` (today's fallback in every pattern). |
| `line_of_sight(from) -> bool` | **stub, returns `has_target`.** The real raycast comes in Phase 4 (sniper, IDEAS §28). |

### 2.7 `AttackController` extension (no second controller)

New exports and API. **Defaults reproduce today exactly.**

- `enabled := true`. When false, the timer still runs but the shot is withheld: "hold fire".
- `driven_by_brain := false`. When true, `_process` is a no-op and the owner calls `tick(delta)`.
- `fire_now()` fires once regardless of the timer. It is for telegraphed shots in later phases.

`AimedAttackPattern` and `GatlingAttackPattern` gain `@export var accuracy: float = 0.0`. They aim through
`TargetInfo.player(tree).aim_direction(ship_pos, bullet_speed, accuracy)`. At `0.0` this is byte-identical to
today's direct aim. Aimed and gatling patterns have no test today, so the task pins their current direction
first and then migrates them. These are the only consumers migrated to TargetInfo in
Phase 1, and they are the "accuracy hook for later difficulty tiers".

### 2.8 `DefenseProfile` and `CollisionLayers`

`CollisionLayers` holds named constants that mirror `project.godot [layer_names]`:

| Constant | Value |
|---|---|
| `ENVIRONMENT` | 1 |
| `ENVIRONMENT_INTERACTABLE` | 2 |
| `ENVIRONMENT_PLAYER` | 4 |
| `PICKUPS` | 16 |
| `PLAYER_ROCKETS` | 32 |
| `PLAYER_HITBOX` | 64 |
| `PLAYER_HURTBOX` | 128 |
| `ENEMY_HITBOX` | 256 |
| `ENEMY_HURTBOX` | 512 |
| `HAZARD_CONTACT` | 1024 |

`DefenseProfile` (`Node`) exports:
- `accepts_player_bullets`, `accepts_player_rockets`, `accepts_environment`, `accepts_hazard_contact`, all
  default `true`
- `accepted_damage_types: Array[HitBox.DamageType]`, default empty, meaning all. This is an *Array export on a
  node*, which is legal. The flat-config rule applies to configs only.
- `alternate_mask_flags` + `apply_alternate()` for a one-way two-state switch. That is exactly the ram's
  33 → 97 and no more. General multi-state armour is Phase 4.

`mask()` computes the int. `apply_to(hurt_box)` writes the mask and the types.

`BaseEnemy._ready()` resolves a `DefenseProfile` child by type. If there is none it creates a default one, so
**no scene needs editing, and the mask is still 1121**. Then it calls `apply_to(hurt_box)`. Line 51 is deleted.

Per-enemy handling:
- **Ram ship:** gets a scene-authored profile with `accepts_player_bullets = false` and
  `accepts_hazard_contact = false` (→ 33 = rockets + environment), and `alternate` = bullets + rockets +
  environment (→ 97, still without 1024, exactly as `ram_ship.gd:45` does today). `ram_ship.gd:21,45` call the
  profile instead of writing ints.
- **Station turret:** `station_turret.gd:34-35` writes 512/1121 itself. It switches to the constants, so it
  stays a non-BaseEnemy writer, with an identical value.

### 2.9 `ProjectileLifetime`

`Node` child of a projectile. It exports `max_time` (s, 0 = off), `max_distance` (px from the origin, 0 = off),
and `use_world_rect := true`. Each rule is checked in the component's own `_physics_process`, which Godot runs
*after* its parent's (tree order), so the host has already moved this frame — the same order as today's
`enemy_bullet.gd:31-37`.

- **Arming (F1).** The component is *unarmed* until either `reset()` is called or its first physics tick,
  whichever comes first. Arming records the origin (`host.global_position`), zeroes the clock, clears the
  latch, and resolves the world rect. On a lazy (first-tick) arm, all three rules are checked on that same tick.
  - Pooled bullets: `EnemyBullet.reset()` calls `lifetime.reset()`, and `BulletPool.acquire()` already sets
    `global_position` *before* `reset()` (`bullet_pool.gd:68-72`), so the origin is the muzzle.
  - The unpooled sniper shot (`sniper_enemy.gd:99-103`: instantiate → `set_direction` → `add_child` → *then*
    `global_position = muzzle`) is never `reset()`. It arms on its first tick, by which time its position is
    set. Its origin is therefore at most one frame of travel past the muzzle (1400 px/s ÷ 60 ≈ 23 px), which is
    immaterial because `max_distance` exceeds the rect diagonal by more than that (below). The rect rule works
    from the first tick, exactly as today.
  - Arming never happens in `_ready()`: at that point the sniper shot is still at the parent's origin.
- The first rule that trips emits the host's `expired` **once**, through `host.expired.emit()` with a
  duck-typed `has_signal`, then latches until the next `reset()`. It never calls `queue_free`.
- `expire_now()` is IDEAS §12's `explicit_destroy()`: it emits the host's `expired` through the same latch
  (so never twice). No Phase 1 caller; it exists for recall-on-owner-death weapons. A hit keeps emitting
  `expired` from the host as today (`_on_hit_box_area_entered`) — that already *is* the explicit destroy for a
  hit, and is unchanged. A hit and a lifetime rule on the same frame can both emit, exactly as a hit and the
  bounds check can today; the pool's deferred `_recycle` already tolerates that, and t13 pins it.
- **World rect:** resolved at arm time through `EnemyWorld.projectile_world_rect(tree)`, i.e. the
  `&"assault_arena"` provider's `projectile_world_rect()`. `ArenaCamera` returns the derived rect **plus 64 px**,
  which equals today's constants exactly: x −164…1444, y −444…1164. The provider is owned by **t4b** (below), so
  t13 never edits `arena_camera.gd`.
- **Race mode:** `RacerWeapon` also fires `EnemyBullet`. `race_level_1.tscn:67-69`'s `Camera2D` already carries
  the `ArenaCamera` script, so once t4b adds the group the race gets the legacy rect with **no race-specific
  wiring**. A race regression test still pins it.
- **`level_2.tscn`** is the one Assault scene with a plain `Camera2D` (`:10`). It is referenced from nowhere, so
  its bullets would fall back to time and distance only. Accepted and noted; removing the dead scene is not this
  epic's job (follow-up).
- **No provider (Open Space):** only the time and distance rules apply.

`enemy_bullet.tscn` gains the node. The defaults are **derived**, not picked, so neither rule can trip inside
today's rect (F2):

- The rect is 1608 × 1608 px, so the longest path inside it is the diagonal, `1608·√2 ≈ 2274 px`. (A shot
  that starts outside the rect expires on its first tick under the rect rule, as today.)
- `max_distance = ceil_to_100(diag + 64) = 2400 px`.
- `max_time = ceil(diag / min_speed) + 2 s`, where `min_speed` is the minimum over **every** shipped enemy-bullet
  speed source:

  | Source | Speed (px/s) |
  |---|---|
  | `station_gunnery.gd:70,75` fallback defaults (`turret_bullet_speed`, `core_bullet_speed`, used only without a config) | **150** |
  | `space_station_config.tres:26` `core_bullet_speed` | 210 |
  | `radial_attack_pattern.gd:41`, `gatling_attack_pattern.gd:10` defaults | 220 |
  | `interceptor_config.gd:11` / `.tres` `bullet_speed`, `interceptor.gd:39` fallback | 220 |
  | `space_station_config.tres:21` `turret_bullet_speed` | 240 |
  | `aimed_attack_pattern.gd:9` default, `enemy_bullet.gd` `speed`/`reset()`, `light_assault_ship.gd:42` aimed | 250 |
  | `gunship_config.tres:13` `bullet_speed` | 260 |
  | racers: `fang_hunt_state.gd:16`, `bg_reclaim_state.gd:17`, `isac_spray_state.gd:11` (via `RacerWeapon`) | 300 / 320 / 360 |
  | `light_assault_ship.gd:42` forward | 420 |
  | `enemy_sniper_bullet.tscn:19` | 1400 |

  `min_speed = 150` → `ceil(2274 / 150) + 2 = 16 + 2` = **18 s**. (Excluding the unused 150 fallback would give
  `ceil(2274/210) + 2 = 13 s`; the fallback is included because it is live code.)
- The t13 test **reads these values from the shipped files** (script defaults via a fresh instance, `.tres` via
  `load()`, racer state exports via instantiation) rather than hardcoding them, recomputes both numbers with the
  same formula, and asserts the shipped defaults are ≥ them. A new, slower bullet source must be added to the
  test's source list; the list is in one array at the top of the file.
- `enemy_bullet.gd:6-16` and the constants go.
- The sniper shot (`enemy_sniper_bullet.tscn`, same script, unpooled) inherits the node and still frees through
  its `expired → queue_free`. The t13 case drives it through the **real** `SniperEnemy._phase_fire()` path with
  an Assault provider present, aims it so it crosses the legacy rect in well under 18 s, and asserts it is freed
  on the frame after crossing — a build that never arms lazily would keep it alive until `max_time` and fail.

`persist_after_owner_death` is written into the component's header as the documented future rule. It will be a
`BulletPool` policy (skip `cancel_active()` for flagged projectiles), built in Phase 5.

`bomb.gd` keeps its own fuse and cull in Phase 1. Its rework is Phase 4's (bomber).

### 2.10 `BaseEnemy` conventions debt

- The death `print` (82) moves behind `if OS.is_stdout_verbose():`.
- `@export var sprite_forward_angle: float = PI / 2`: the direction the *art's nose* points in texture space.
  The default is nose-down, the Assault path-mover convention. The mover's facing rule (§2.4) uses it.
  - The ported interceptor sets `-PI/2` (nose-up). `atan2(dir.x, -dir.y)` equals `dir.angle() + PI/2`, so its
    facing is unchanged.
  - `_rotate_sprite()`'s 180° flip of a child `AnimatedSprite2D` (light assault ship, ram ship) is **kept and
    documented** as child-sprite art correction. It is characterised, not changed, because it is a separate
    concern from body facing.
- `_on_received_damage(damage)` and `_on_health_changed(current)` get `##` docs naming them as the virtual
  damage/death hooks, the contract subclasses (the space station) override.
- **Stale `base_enemy.gd:<line>` references (F9)** are *not* fixed piecemeal: t5, t6 and t10 each renumber the
  file. t15 runs `grep -rn "base_enemy.gd:[0-9]"` over the whole repo against the final file and rewrites every
  hit to cite the **symbol** (`BaseEnemy._on_health_changed`, …) rather than a line. Known hits today:
  `space_station.gd:184`, `station_turret.gd:31`, `space_station/ENEMY.md:350,475`,
  `docs/architecture/modules/assault.md:420`, `tests/README.md:330`, `test_station_reinforcements.gd:372-373`,
  `test_station_death_sequence.gd:58`. Tests' *comments* only are edited; no assertion changes.
- `suspend_ai()`: sets `_ai_suspended`, calls `_brain.on_suspended()`, and zeroes `velocity`. It is idempotent.
  `EnemyPathMover._ready()` then does **all three, unconditionally** (F3):
  1. `set_physics_process(false)` on the actor (today);
  2. the `"AIStateMachine"` name lookup → `PROCESS_MODE_DISABLED` (today; the light assault ship's states
     write `velocity` and call `move_and_slide()` from `StateMachine._process`, which step 1 does not stop);
  3. `_actor.suspend_ai()` if `has_method` (new).
  No branch makes 2 depend on 3. Every existing enemy is suspended exactly as today, and brain-driven enemies are
  suspended through the contract as well. t2 pins this on the **real** `light_assault_ship.tscn` (see §4).
- `ShipConfig` gets `@export_group("Defense")` around `max_health` / `collision_damage` and `"Scoring"` around
  the score fields (P-3). Export groups change no values and no serialization.

### 2.11 The Drone Interceptor port

`drone_interceptor.gd` loses its `_physics_process` and its phase logic. `drone_interceptor.tscn` gains
`EnemyMover` + `DroneInterceptorBrain` children; the brain holds ENTER/ORBIT/DASH as an enum. Its tuning is read
from the unchanged config. Behaviour is kept 1:1:

| Behaviour today | Kept how |
|---|---|
| ENTER: straight at the player at `approach_speed` until within `orbit_radius` | `Steering.seek` |
| ORBIT: the angle advances at `orbit_speed`; correction speed is `clamp(dist·4, 60, orbit_correct_speed)`; dashes when a 1–2 s timer expires | `Steering.orbit`; the timer is `rng.randf_range(1,2)` |
| DASH: direction locked to `TargetInfo.player().predicted_position(dash_prediction_time)` at `dash_speed` | same |
| Facing: lerp 7.0 toward the player (ENTER/ORBIT) or the dash direction | `face_toward` + `turn_lerp = 7` |
| Contact kill | unchanged |

- **Randomness:** `randf_range` for the initial orbit angle and the dash timer moves to `brain.rng`.
- **No target at dash onset:** today's fallback (`predicted = position + (0, 200)`, i.e. straight down,
  `drone_interceptor.gd:119-120`) is kept by the brain explicitly; `TargetInfo` with `has_target = false`.
- **Constraint: `constraint_mode = NONE` in Phase 1 (F4, option a).** Today the drone has no corridor; under AUTO
  it would get one in level 1 and deviate at the corridor edge (§2.5 *Phase 1 consumers*). With NONE the port is
  1:1 in Assault. Every legacy cull bound (x −80…1360, y −80…800) lies inside the corridor's `visible` rect, so
  the dash still ends exactly where it does today. Phase 2 (Razor Drone) turns the corridor on and re-pins.
- **Dash end, Assault:** the exact legacy cull (camera `global_position ± viewport/2 ± 80`, which ignores
  `cam.offset`, `drone_interceptor.gd:129-140`) moves to the provider as `ArenaCamera.enemy_cull_rect()`,
  read through `EnemyWorld.cull_rect(tree)` (t4b). The brain frees the drone when a DASH position leaves that
  rect. It is a provider method, not a constraint method, precisely because the drone runs with no constraint.
  That keeps today's quirk identical.
- **Dash end, Open Space:** today's `_check_off_screen` would cull against the Open Space camera, which is a
  child of `PlayerShip` (`sector_hub.tscn:83`) and so moves with the player: a missed dash is culled roughly a
  screen away from wherever the player happens to be. That is a screen-visibility lifetime rule, which IDEAS
  §3.3 / §38 rejects for Open Space. So with no provider the brain uses a new flat config field
  `dash_max_distance = 1600` px (judgement: a little more than a 1280 px screen width plus the orbit radius),
  measured from the dash start; past it the drone frees itself. It stays a one-way kamikaze; leash/return is
  Phase 13's.
- **Station reinforcements do not use it.** `test_station_reinforcements.gd:318-326` asserts the opposite of
  what revision 1 claimed: the drone interceptor is self-managed AI and no squad may use it. The only live
  spawns are level 1's two, `level_1_director.gd:290-291`. That test stays green unchanged, and the playtest
  eyeball item is level 1's two drone interceptors only.

**Why acceleration = 0 for the port:** today's code assigns `velocity` directly. Non-zero acceleration would
change its feel, and that is Phase 2's (Razor Drone) call.

### 2.12 What is *not* changing in Phase 1

- `EnemyPathMover`'s position model, `WaveManager`, `WaveBuilder`, every level file, and every other enemy's
  movement.
- `BulletPool`'s container (P-18).
- `bomb.gd`.
- `DamageReaction`.
- PatrolDrone's code: characterised only.

---

## 3. Build sequence

Each step is one task in `tasks.json` (key in brackets). Characterization comes first, so every refactor lands
against a pin.

1. **[t1-pin-base-enemy]** Characterise `BaseEnemy` over the live roster: the post-`_ready()` hurtbox mask of
   every enemy (1121; ram 33 → 97 after its first received hit; station turret 1121), the damage → flash → death
   flow, `died` then free, scoring fields copied from config, and the `AnimatedSprite2D` 180° flip. The roster is
   `assault/scenes/enemies/<dir>/<dir>.tscn` whose instantiated root `is BaseEnemy` (the
   `test_config_instance_isolation.gd` sweep shape), so `bomber/bomb.tscn` is excluded; the station turret is an
   explicit extra case.
2. **[t2-pin-path-mover]** Characterise `EnemyPathMover`: sample × `WORLD_SCALE` offset from the spawn point,
   actor physics suspended, `AIStateMachine` disabled, both exit modes, the off-screen cull (80 px margin,
   never-on-screen actor not culled), the no-camera warning path, and nose-down facing. **Plus a case on the real
   `light_assault_ship.tscn`** (F3): mover attached → `AIStateMachine.process_mode == DISABLED`, and the position
   equals the path sample after N frames.
3. **[t3-pin-drones]** Characterise PatrolDrone (drift, scene-wired damage, `died` + free, mask 64 and the
   rocket immunity, body layer 256) and the Drone Interceptor (ENTER→ORBIT at the radius, orbit speed clamp,
   dash direction = predicted position, dash speed, contact kill, facing). Assertions are **seed-robust** (F10):
   the dash begins within [1.0, 2.0] s of ORBIT entry (boundary: never before 1.0 s; always by 2.0 s + one
   frame), and the orbit is checked by radius, not by angle, so they survive the RNG moving to `brain.rng`.
4. **[t4-layers]** Name layers 3/5/6/11, add `CollisionLayers`, and add the invariant test
   `test_collision_layer_names.gd`.
5. **[t4b-arena-provider]** `ArenaCamera` joins `&"assault_arena"` with `projectile_world_rect()` and
   `enemy_cull_rect()`; `EnemyWorld` lookup helper (§2.5a). Small; the sole first owner of `arena_camera.gd`.
6. **[t5-defense-profile]** `DefenseProfile`; BaseEnemy default profile; ram ship and station turret onto it.
   Step 1's pins stay green unchanged.
7. **[t6-base-enemy-debt]** Verbose-gated death print, `sprite_forward_angle`, documented virtual hooks,
   `ShipConfig` export groups. **Depends on t5** (F5): both edit `base_enemy.gd`. The stale line-reference fix
   moved to t15 (F9).
8. **[t7-target-info]** `TargetInfo`, with unit tests.
9. **[t8-attack-controller]** `AttackController` extension, and `accuracy` on the aimed and gatling patterns.
10. **[t9-steering]** `Steering` primitives, with unit tests.
11. **[t10-brain-mover]** `EnemyBrain`, `EnemyMover` (with `braking` and `max_turn_rate`), `MovementConstraint`,
    the BaseEnemy tick loop, `suspend_ai()`, the path mover's additional duck-typed suspension (the name lookup
    stays unconditional), a test fixture enemy, and the single-writer source sweep.
12. **[t11-corridor]** `AssaultCorridorConstraint` (§2.5, full band spec) and
    `ArenaCamera.enemy_movement_constraint()`. Depends on t4b and t10.
13. **[t12-dual-harness]** The dual-mode harness helper, and the fixture behaviour spec in both modes.
14. **[t13-projectile-lifetime]** `ProjectileLifetime` (lazy arming, derived defaults), the EnemyBullet migration,
    and regression tests (race, sniper via the real fire path). Depends on t4b only.
15. **[t14-port-interceptor]** Port the Drone Interceptor (`constraint_mode = NONE`), and its behaviour spec in
    both modes.
16. **[t15-docs]** Docs pass (`updating-project-docs`), the repo-wide `base_enemy.gd:<line>` sweep, and the phase's
    *as built* notes.

Parallelism: the t1–t3 pins, t4, t4b and t7 are independent of each other. t13 can start as soon as t4b lands.
The `base_enemy.gd` chain is strictly t1 → t5 → t6 → t10 (t4 → t5 too); `arena_camera.gd` is t4b → t11.

---

## 4. Test plan

All tests are GUT, deterministic, and use `simulate(node, n, 1.0/60.0)` or direct `tick()`/`step()` calls. No
test awaits a `Timer`. Fixtures live under `tests/helpers/` (never named `test_*`). Any new `await` is followed by
`scripts/check-test-leaks.sh`.

| File | Kind | Cases (at least one boundary each) |
|---|---|---|
| `tests/integration/test_base_enemy.gd` | characterization, then intent for the new hooks | Mask per roster enemy equals the pinned value. Roster = `assault/scenes/enemies/<dir>/<dir>.tscn` whose root `is BaseEnemy` (so `bomb.tscn` is out), plus `space_station/station_turret.tscn` as an explicit extra case; a new enemy dir is covered automatically. The ram mask goes 33 → 97 on its first received hit (a rocket or environment hit, since 33 excludes bullets) and never goes back; lethal damage → `died` emitted once, `was_killed`, freed; non-lethal → no `died`; scoring copied from config; `AnimatedSprite2D` rotation 180; **boundary:** an enemy with a scene `DefenseProfile` is not given a second one (after t5); **boundary:** death print absent without `--verbose` (asserted structurally: the `print` is inside an `is_stdout_verbose()` branch, same approach as the signal-arity sweep; after t6) |
| `tests/integration/test_enemy_path_mover.gd` | characterization | Position = spawn + sample(t)·2.0 after N frames; actor `is_physics_processing()` false; `AIStateMachine` disabled; FREE_ON_DURATION frees at `exit_time` and at `total_duration()` when 0; **real `light_assault_ship.tscn` case (F3):** after attaching a mover, `AIStateMachine.process_mode == PROCESS_MODE_DISABLED` and position == path sample after N frames — this stays in the file after t10 and fails if the name lookup is ever made conditional on `suspend_ai()`; after t10 also: `suspend_ai()` called when present *and* the name lookup still ran; **boundary:** an actor spawned off-screen and never entering is not culled; an actor that entered then left by more than 80 px is culled; exactly 80 px is not |
| `tests/integration/test_patrol_drone.gd` | characterization | Drifts `initial_direction·move_speed`; zero direction → RIGHT; a scene-wired HitBox overlap decreases health; health 0 → `died` + freed; **characterization of a bug:** HurtBox mask == 64 (rockets pass through), body layer 256 |
| `tests/integration/test_drone_interceptor.gd` | characterization *before* the port, **the port's acceptance test after it** | No player → zero velocity; ENTER velocity = approach_speed toward the player; enters ORBIT at ≤ orbit_radius (**boundary:** exactly the radius); orbit holds the radius (asserted by distance, not by angle); orbit correction speed clamped to [60, orbit_correct_speed]; **seed-robust dash onset (F10):** the dash begins within [1.0, 2.0] s of ORBIT entry — boundary: no dash at 1.0 s − 1 frame, a dash by 2.0 s + 1 frame, for several seeds; the dash direction uses `player.velocity·0.2`; no player at dash onset → straight down; dash speed 480; contact → health 0; facing converges to nose-up toward the player; in an Assault world, the dash ends past the legacy cull rect (x −80…1360, y −80…800 at a 1280×720 viewport) |
| `tests/unit/test_target_info.gd` | intent | No target → `has_target` false, `aim_direction` DOWN; `predicted_position(0)` = position; stationary target → intercept ok, time = dist/speed; **boundary:** a target moving away faster than the shot → `ok = false`, point = position; `shot_speed = 0` → not ok; a target at the shooter's position → ok, time 0, no NaN; accuracy 0 = direct, 1 = intercept, 0.5 = midpoint; a target freed after the snapshot → reading members is safe |
| `tests/unit/test_steering.gd` | intent | Each primitive's direction and magnitude; `arrive` → speed 0 at the target and full speed outside the derived radius; `orbit` anchor and clamp match the interceptor formula; `strafe` ⟂ the target line for both `side` values; `hold_position` is zero inside the tolerance; **boundary:** zero vectors or a coincident target never return NaN |
| `tests/unit/test_enemy_mover.gd` | intent | Accel limit caps the velocity change per step; `braking` caps a slow-down separately, and `braking = 0` falls back to `acceleration`; `acceleration = 0` is instant; max_speed truncates; the constraint filter is applied; `constraint_mode = NONE` never resolves one even with a provider present; the facing rule with `sprite_forward_angle` ±PI/2, read duck-typed (an actor without the property uses PI/2); `max_turn_rate` caps the rotation change per step, 0 = uncapped; `boost` overrides for `duration` and then ends; **boundary:** not a CharacterBody2D parent → warning, disabled, no error |
| `tests/unit/test_enemy_world.gd` | intent | No provider → `arena()` null, no rect, no cull, no constraint; an `ArenaCamera` in the tree → `projectile_world_rect()` == x −164…1444, y −444…1164; `cull_rect()` == camera position ± viewport/2 ± 80; a provider without `enemy_movement_constraint()` → null (the t4b state); **boundary:** a plain `Camera2D` (the `level_2.tscn` shape) is not a provider |
| `tests/unit/test_assault_corridor_constraint.gd` | intent | Inside visible → identity; per-axis: a lateral velocity is untouched while the vertical axis is filtered; band 2 (0 < d ≤ 120) → outward kept, pressure `edge_pressure·d/120` px/s; band 3 (120 < d < 450) → full pressure, outward scaled linearly to 0 at 450; band 4 (d ≥ 450) → no outward component and net inward ≥ `edge_pressure` whatever the input ("forced to re-enter"), tangential kept (slides, never stalls); **boundaries:** d = 0, 120, 450 exactly; not-entered: a spawn at y = −860 (beyond the hard edge) with outward intent gets inward ≥ `entry_speed` on y and keeps its x velocity until entered, then the latch holds; the derived rect == ArenaCamera constants |
| `tests/integration/test_enemy_brain_contract.gd` | intent | The BaseEnemy loop ticks brain then mover once per physics frame; `suspend_ai()` stops both and zeroes velocity; `EnemyPathMover` attached → brain suspended and path position exact; the rng is seedable (same seed → same sequence); an enemy without a brain → the base loop is inert (the legacy subclass path is unchanged) |
| `tests/integration/test_enemy_mover_single_writer.gd` | invariant (F10) | Source sweep (§2.4): every `*_brain.gd`, every `global/enemy_ai/*.gd` except `enemy_mover.gd`, and the root script of every enemy scene containing an `EnemyMover`, has no `velocity`/`rotation` assignment and no `move_and_slide(`; empty permanent allowlist; **boundary:** a synthetic source string with `rotation = 0.0` is reported, proving the sweep can fail |
| `tests/integration/test_enemy_dual_mode.gd` | intent (IDEAS §40) | `use_parameters([open_space, assault])` over the fixture (corridor AUTO) and the ported interceptor (NONE): reaches orbit; the fixture holds the radius within tolerance *or* stays inside the soft band when clamped; the dash direction is identical in both modes for the same seed and positions; the assault harness spawn above the screen enters; the interceptor's Assault orbit is identical to its Open Space orbit for the same inputs (no constraint in Phase 1); the open_space interceptor frees after `dash_max_distance` |
| `tests/unit/test_projectile_lifetime.gd` + `tests/integration/test_enemy_bullet_lifetime.gd` | intent + regression | Each rule trips alone; `expired` fires exactly once per life and never `queue_free`s (checked via `BulletPool.acquire()` reuse, not `_idle.size()`, per the player-bullet-lifetime precedent); `reset()` re-arms; `expire_now()` emits once; **lazy arm (F1):** a component never `reset()` arms on its first tick with the host's position at that tick, never in `_ready()`; **the unpooled sniper shot through the real `SniperEnemy._phase_fire()`** with an Assault provider, aimed to cross the legacy rect in < 18 s, is freed the frame after crossing; **boundary:** a bullet at x = 1444 lives and at 1444.1 expires with the Assault provider; with no provider the same position lives; **derived defaults (F2):** the test reads every speed source listed in §2.9 from the shipped files, recomputes `ceil(diag/min_speed) + 2` and `ceil_to_100(diag + 64)`, and asserts `max_time`/`max_distance` in `enemy_bullet.tscn` are ≥ them; the race bullet still expires at the legacy rect (the race's `ArenaCamera` is the provider; no race wiring) |
| `tests/integration/test_collision_layer_names.gd` | invariant | Every bit set in any `.tscn`/`.tres` `collision_layer`/`collision_mask` outside `addons/` has a `[layer_names]` entry; every `CollisionLayers` constant equals `1 << (n-1)` for the layer whose name matches; **boundary:** a synthetic mask with bit 4 (8) is reported as unnamed |
| `tests/integration/test_attack_controller.gd` | intent | Default path unchanged (existing users' cadence); `enabled = false` withholds shots but keeps the phase; `driven_by_brain` → `_process` inert, `tick` fires; `fire_now` fires immediately; aimed/gatling `accuracy = 0` → same direction as today |

Existing gates that must stay green untouched: config isolation, contact-damage, contact-hitbox geometry, hurtbox
geometry, player-bullet lifetime, signal arity, rotation single-writer, project load integrity, the station
family, `test_ram_ship.gd`, `test_radial_attack_pattern.gd`, `test_level_1_sequence.gd`.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| The BaseEnemy `_physics_process` accidentally runs for legacy subclasses | Subclass overrides replace it. The loop is inert without a brain. `test_enemy_brain_contract` pins "no brain → inert". |
| Two position writers (path mover + mover, or path mover + a legacy `AIStateMachine`) | The path mover calls `suspend_ai()` *and* keeps `set_physics_process(false)` *and* the unconditional name lookup (§2.10); the real light-assault-ship case in t2 fails if the lookup is ever made conditional; pinned in t2 and t10. |
| The mask regresses for one enemy | t1 pins every roster mask *before* t5 touches line 51. |
| The race breaks from the EnemyBullet change | The race scene already uses `ArenaCamera`, so it gets the provider from t4b with no wiring; a race regression test in t13. |
| An unpooled projectile is never armed | Lazy arming on the first tick (§2.9); the sniper shot is tested through its real fire path. |
| A lifetime default trips inside today's rect | Defaults are derived from every shipped speed source, and the t13 test recomputes them from the files (§2.9). |
| The interceptor behaves differently in Assault once a corridor exists | It runs with `constraint_mode = NONE` in Phase 1 (§2.11); the dual-mode test asserts its Assault orbit equals its Open Space orbit. |
| Parallel tasks edit the same file | `base_enemy.gd`: t1 → t5 → t6 → t10 strictly. `arena_camera.gd`: t4b → t11. Stale line references are fixed once, in t15. |
| The port changes feel | t3 pins the numbers before t14; `acceleration = 0`; the same config. The playtest feel is a human eyeball item in the dossier. |
| `test_project_load_integrity` fails on new components | Components warn, never error, when instantiated bare; the fixture enemy lives under `tests/helpers/`. |
| New `class_name`s collide | Names were checked against the project: `MovementController` is taken (hence `EnemyMover`); `TargetInfo`, `Steering`, `EnemyBrain`, `DefenseProfile`, `ProjectileLifetime`, `CollisionLayers` and `MovementConstraint` are free today, as are `EnemyWorld`, `AssaultCorridorConstraint` and `DroneInterceptorBrain`. The implementer re-greps before adding. |
| A UID mishap on the new `.gd`/`.tscn` edits | New files are UID-less or headless-minted, never copied (CLAUDE.md). |
| Signal arity | New signals are declared with their emitted args. `ProjectileLifetime` declares none; it emits the host's. |

---

## 6. Out of scope for Phase 1, and why

- Any new enemy, any enemy other than the Drone Interceptor migrating onto brains, and any change to wave
  movement or levels: Phases 2–15.
- The `BulletPool` container: Phase 2 (P-18).
- Line-of-sight raycasts: Phase 4. Hazard perception and context steering: Phase 6.
- Leash, search and encounter ownership: Phase 13. Idle profiles: Phase 14.
- Difficulty tiers: Phase 16. Only the `accuracy` hook ships now.
- `persist_after_owner_death` as code: Phase 5. `DamageReaction` adoption: Phase 5.
- The art readability pass: per roster phase, audited in Phase 17.
- Moving `BaseEnemy` to `global/`: Phase 15.
- The corridor on the Drone Interceptor: Phase 2 (Razor Drone), §2.11.
- Retiring `EnemyPathMover`'s `"AIStateMachine"` name lookup: Phase 15, once the light assault ship's state
  machine is on a brain (§2.10).
- IDEAS §12 `max_distance_from_owner` (as opposed to from the origin) and `max_distance_from_player`: Phase 5
  (owner-bound projectiles, together with `persist_after_owner_death`) and Phase 13 (encounter ownership).
- Removing the unreferenced `assault/scenes/levels/level_2.tscn`: not this epic; listed as a follow-up.
- IDEAS §3.1's `turn_rate` and `braking` are **in** scope (as `EnemyMover.max_turn_rate` and `braking`, §2.4);
  revision 1 had silently dropped them.

---

## 7. Roadmap: the full idea split into the 19-phase chain

Each phase lists what it takes from the ideas and which Phase 1 interfaces it builds on. Per the phase
convention, each phase re-validates its scope against what the previous phase *actually* built (`DECISIONS.md`).

| Phase | Scope (IDEAS §§) | Builds on from Phase 1 | Also owns |
|---|---|---|---|
| **1 Architecture** (this) | §1.3, §3.1, §3.2 (9 primitives), §4 contract, §12, §15, §27, §30, §34, §39, §40 (harness), §41 Ph1 | — | Drone Interceptor port; characterization tests |
| **2 Swarm Drone, Razor Drone, squad roles** | §5.1, §5.2, §17 (lead/flank roles only), §16 (contact profiles: None/Collision/Ramming), §2 PatrolDrone retirement | brain, mover, `Steering`, `TargetInfo`, dual harness | `spiral`/`corkscrew`/`formation_slot`; Razor Drone evolves the ported interceptor (feint, fake dash, pulse); **`BulletPool` injectable container** (P-18); Open Space Swarm replaces `SectorHub`'s drones |
| **3 Fighter, Gatling Interceptor, bullet family** | §5.3, §5.4, §11.1 | `AttackController` (hold fire, `driven_by_brain`), `accuracy`, `TargetInfo.aim_direction` | pressure-window cadence; convergence fire; `lead_target` |
| **4 Bomber, Sniper, Ram Corvette** | §5.5–5.7, §28 LOS, §31 (sniper `FLY_IN_TIME` coupling) | `DefenseProfile` (ram plates → multi-state or deflection, P-5), `TargetInfo.line_of_sight` becomes real, `ProjectileLifetime` for bombs | `break_contact`; `bomb.gd` lifetime rework; the Bonus Drone kept as an Assault reward (§38) |
| **5 Missile Corvette, rockets, Support/Shield Ship** | §6.1, §6.2, §11.2 (except the hijack pulse), §13.2 shields | `ProjectileLifetime` + **`persist_after_owner_death` as pool policy**, `TargetInfo.intercept` for rockets | **`DamageReaction`/Shield adoption decision (P-15)** |
| **6 Hazard perception, gravity wells, anomalies, wrecks** | §3.2.5, §6.7, §6.8, §18.6 | `EnemyMover` nudge slot → **context steering upgrade**, `MovementConstraint` | allocates layer 12 `area_control` in `CollisionLayers` (P-6) |
| **7 Mines, minefields, Mine Layer** | §6.3, §6.9, §11.4 (mine, gravity field) | hazard layer (6), `ProjectileLifetime` (persistent) | |
| **8 Energy weapons, turrets, Twin-Laser Drones** | §6.5, §6.10, §11.3 | `AttackController.fire_now` (telegraphs), `TargetInfo` | beam/laser-wall family |
| **9 Electronic warfare** | §6.4 Hacker Frigate + §11.2 hijack pulse, §6.6 Jamming Structure, §11.4 EMP | hazard fields (6) | the player's seeking weapons must expose retargeting |
| **10 Modular damage, Heavy Gunship, Carrier** | §7, §6.11, §13.3, §14, §26 | `DefenseProfile` per module; generalises the station's turret pattern | Gunship's screen-top parking scrapped (§38) |
| **11 Space Fortress 2.0 + machine-driven reinforcements** | §8.1, §10, §24, §25 | module framework (10), brains | the Space Station rework keeps its modular structure (§39) |
| **12 Dreadnought** | §9 | module framework (10) | |
| **13 EncounterDirector + encounter-owned lifecycle** | §3.3, §19, §32, §33 | `TargetInfo`, brains; the no-constraint mode | leash / search / reacquire; semantic spawn positions; Salvage Drone world event (§2, §38) |
| **14 Squad communication, idle profiles, emergent encounters** | §18, §18.5, §35, §37, §42 | brains, `EnemyMover` | `regroup`; SquadController messages |
| **15 Assault migration** | §20, §34 (full), §35 | `AssaultCorridorConstraint`, `suspend_ai` | formations become spawn layouts; `EnemyPathMover` retired as the default; `BaseEnemy` moves to `global/` |
| **16 Behaviour-driven difficulty tiers** | §29 | `accuracy` hook; telegraph and cooldown fields in config groups | |
| **17 Readability pass, checklist audit, cleanup** | §21–23 (audited), §43 checklist, §38 scrap-list leftovers | — | art runs under the `pixel-art-generation` skill in each roster phase; this phase audits and cleans up |
| **18 Carrier and Heavy Gunship on the shared boss machinery** | §10 (module-tied launches), §24 (geometry weapons), §25 (phase rules) applied to the Phase 10 heavies | module framework (10), boss machinery (11), `DefenseProfile` per module, brains | the Carrier's hangar-tied launches and the Gunship's battery-loss phases reuse Phase 11's reinforcement and phase rules instead of bespoke code |
| **19 Hazards, line of sight and wrecks for heavy ships and bosses** | §3.2.5 / §18.6 (hazard response by mass), §28 LOS, §6.8 wrecks, §14/§26 (destroyed modules remain) for Phases 10–12 and 18 | hazard perception + context steering (6), real `line_of_sight` (4), `EnemyMover` constraint/nudge slot | heavy-ship resistance to gravity wells; destroyed modules as LOS-blocking wreckage |

---

## 8. Requirements coverage

Every Phase 1 requirement maps to task keys. Everything else maps to the phase that owns it. Nothing is dropped.

| Requirement (source) | Delivered by |
|---|---|
| R1 mode-neutral BaseEnemy (IDEAS §41.1) | t5, t6, t10 (the file move is Phase 15) |
| R2 brain / mover / attack / defense contracts (§3.1) | t10 (brain, mover — including §3.1's `turn_rate` as `max_turn_rate` and `braking`), t8 (attack), t5 (defense) |
| R3 movement primitives (§3.2) | t9, t10 (seek, arrive, orbit, intercept, evade/retreat_from, strafe, hold_position, drift, boost). Others: spiral/corkscrew/formation_slot → Ph2; lead_target → Ph3; break_contact → Ph4; regroup → Ph14 |
| R4 Assault constraint (§1.3, §34) | t4b (provider), t11 (bands incl. "forced to re-enter"), t12; first real enemy on it → Ph2 |
| R5 world-aware projectile lifetime (§12) | t13: `max_time`, `max_distance` (from the origin), `world_bounds` (the provider rect), `explicit_destroy()` as `expire_now()`; `persist_after_owner_death` documented in t13, built in Ph5; `max_distance_from_owner` → Ph5 (with owner-bound projectiles); `max_distance_from_player` → Ph13 (needs encounter ownership) |
| R6 name every used layer (§15) | t4 |
| R7 DefenseProfile replaces the hardcoded mask (§15) | t5 |
| R8 TargetInfo (§27) | t7; the real `line_of_sight` → Ph4 |
| R9 keep-list (§39) | t1–t3 pins; t14 (the interceptor kept); privatise and attack patterns untouched; the station is covered by the existing gates; the Bonus Drone is unchanged (Ph4 note) |
| R10 existing waves unchanged | t2, t10 (the path mover stays the writer); the existing level tests |
| R11 existing gates pass | every task; listed in §4 |
| R12 BaseEnemy / PathMover / PatrolDrone tests + both modes | t1, t2, t3, t12, t14 |
| R13 magic-number coupling (§31) | the layer and mask ints → t4/t5; the bullet rect → t13; the corridor derived from ArenaCamera → t11; sniper `FLY_IN_TIME` → Ph4; spawn maths → Ph13/15; the BulletPool grandparent → Ph2 |
| R14 central player lookup (§27) | t7 resolver; t8 patterns; t14 interceptor. Other enemies migrate in their own phases |
| Scope: suspend_ai, verbose print, sprite_forward_angle, one facing rule, virtual hooks | t6, t10 |
| Scope: accuracy hook for difficulty | t7, t8 |
| Scope: §4 tick on physics, delta accumulators, seedable RNG | t10 |
| Scope: §30 profile groups kept flat | t6 (ShipConfig), t14 (interceptor config) |
| L1 hazards (§3.2.5, §18.6) | Ph6; heavy ships and bosses Ph19 |
| L2 persistence (§3.3, §33) | Ph13 |
| L3 shared combat states (§4) | vocabulary documented in t10; used from Ph2 |
| L4 Swarm, Razor, Fighter, Gatling | Ph2, Ph3 |
| L5 Bomber, Sniper, Ram, Missile, Support | Ph4, Ph5 |
| L6 structures (§6.3–6.10) | Ph6–Ph9 |
| L7 Heavy Gunship, Carrier | Ph10; moved onto the boss machinery in Ph18 |
| L8 bosses (§8–10, §24–26) | Ph11, Ph12 (and Ph10 for §26); §10/§24/§25 for the heavies Ph18 |
| L9 weapon families (§11) | Ph3 bullets, Ph5 rockets, Ph8 energy, Ph7/Ph9 area control |
| L10 armour / shields / weak points / modules (§13–14) | Ph4 armour, Ph5 shields, Ph10 modules and weak points |
| L11 contact-damage profiles (§16) | Ph2 (None/Collision/Ramming), Ph4 (Armour), Ph7 (Explosive) |
| L12 dynamic formations and squad messages (§17, §18, §35) | Ph2 (roles), Ph14 (messages, regroup), Ph15 (spawn layouts) |
| L13 idle profiles (§18.5) | Ph14 |
| L14 EncounterDirector (§19, §32) | Ph13 |
| L15 Assault migration (§20, §34–35) | Ph15 |
| L16 readability art (§21–23) | each roster phase; audit in Ph17 |
| L17 line of sight (§28) | Ph4; heavy ships and bosses Ph19 |
| L18 difficulty (§29) | Ph16 (hook: t7/t8) |
| L19 config groups (§30) | P-3; t6 now, each enemy's phase later |
| L20 Bonus Drone / Salvage Drone (§2, §38) | kept unchanged; Salvage event → Ph13 |
| L21 test strategy (§40) | the harness in t12; every phase adds its enemies to it |
| §42 final design target, §43 checklist | Ph14 (emergent), Ph17 (checklist audit) |

---

## 9. Open questions resolved by this plan

| Question | Answer |
|---|---|
| Numeric layer allocation | Unchanged; names only (P-6). |
| `DamageReaction` in BaseEnemy | Not in Phase 1; revisited in Phase 5 (P-15). |
| Difficulty tiers | Deferred to Phase 16; the `accuracy` hook ships now (P-11). |
| The mover's name | `EnemyMover`. |
| Brain clock | Physics, via `tick` (P-9). |
| Path mover coexistence | `suspend_ai()` *in addition to* the unconditional name lookup and `set_physics_process(false)` (P-10). |
| DefenseProfile shape | A node (P-4). |
| A real consumer or a fixture | Both: the interceptor plus a `tests/helpers/` fixture (P-8). |
| PatrolDrone's rocket immunity | Pinned, not fixed (P-16). |
| How the mode is known | The `&"assault_arena"` duck-typed provider, looked up only through `EnemyWorld` (P-13). |
| Corridor on the ported interceptor | Not in Phase 1 (`constraint_mode = NONE`); Phase 2. |
| Number of phases | 19, as on the board (P-14). |

---

## 10. Response to feedback (plan review round 1, `4-review.md`)

| # | Finding | What changed |
|---|---|---|
| F1 | `ProjectileLifetime` only armed in `reset()`; the unpooled sniper shot is never reset | §2.9: the component **arms lazily** on its first physics tick or on `reset()`, whichever is first, never in `_ready()`. The t13 test drives the sniper shot through the real `SniperEnemy._phase_fire()` path and requires it to be freed on crossing the legacy rect, well before `max_time`. P-12 updated. |
| F2 | `max_time = 10 s` was wrong (slowest bullet 210, not 250) | §2.9: formula `ceil(diag / min_speed) + 2 s` over an enumerated table of **every** speed source, including the station config, the pattern defaults, gunship, racers and the `station_gunnery.gd` fallback (150) → **18 s**; `max_distance = ceil_to_100(diag + 64) = 2400`. The test reads the sources from the files. `DECISIONS.md` corrected. |
| F3 | The name lookup could be read as a fallback and disabled for the light assault ship | P-10 and §2.10: `set_physics_process(false)`, the `"AIStateMachine"` lookup and `suspend_ai()` all run **unconditionally**. t2 adds a case on the real `light_assault_ship.tscn` (state machine disabled, position == path sample), which stays in place through t10. |
| F4 | AUTO corridor makes the interceptor deviate; band spec incomplete | Option (a): the interceptor runs with `constraint_mode = NONE` in Phase 1 (§2.11, P-8); its Assault dash end moves to the provider's `enemy_cull_rect()`. §2.5 now specifies per-axis behaviour in four bands (inside / soft / outer / beyond hard), the pressure units (px/s, `edge_pressure` = 200), the outer-band scaling, what "forced to re-enter" means, and that the hard band does not apply before the entered latch (the y ≈ −860 spawn). |
| F5 | t5/t6 and t11/t13 file collisions | t6 depends on t5. The `ArenaCamera` provider moved into a new small task **t4b-arena-provider** (§2.5a) that t11 and t13 both depend on; only t4b → t11 edit `arena_camera.gd`, in sequence. §3's parallelism line rewritten. |
| F6 | Factual errors | §2.11: the station reinforcements never use the drone interceptor (the test asserts it); the eyeball item is level 1's two drones only. §2.9: no race wiring — `race_level_1.tscn` already uses `ArenaCamera`; `level_2.tscn` (plain `Camera2D`, unreferenced) noted as accepted. §2.11: the Open Space rationale now says today's cull *would* fire against the player-attached camera and that this is the screen-visibility rule IDEAS rejects. P-2: two enemies plus the ally fighter. P-6: IDEAS' 2048 meaning is distinct and adopted in Phase 6; only the 4096 objection stands. |
| F7 | 17 vs 18 phases | The board now shows **19** phases (18 and 19 were added after revision 1). §7 maps both, the coverage table points to them, P-14 and `DECISIONS.md` say 19. |
| F8 | `turn_rate`, `braking`, `max_distance_from_owner`, `explicit_destroy()` dropped silently | `EnemyMover` gains `braking` and `max_turn_rate` (rad/s, 0 = off) (§2.4, t10). §2.9: `expire_now()` is `explicit_destroy()`; distance-from-origin replaces distance-from-owner with the reason; owner distance → Phase 5, player distance → Phase 13 (§6, §8). |
| F9 | Stale `base_enemy.gd:<line>` refs incomplete and fixed too early | Moved from t6 to t15 as a repo-wide `grep -rn "base_enemy.gd:[0-9]"` sweep that rewrites hits to cite symbols (§2.10 lists the eight known hits). |
| F10 | Unenforced single-writer; seed-fragile t3; loose t1 sweep | New invariant `test_enemy_mover_single_writer.gd` (t10, §2.4). t3's dash onset asserted as a [1.0, 2.0] s window with boundaries, orbit by radius. t1's roster is `<dir>/<dir>.tscn` with a `BaseEnemy` root plus the turret as an explicit case. |
| F11 | `global/` typed against `BaseEnemy` | `EnemyBrain.actor` is `CharacterBody2D`; `sprite_forward_angle` is read duck-typed with a `PI/2` default (§2.3, §2.4). |
