# Enemy rework, phase 1: a mode-neutral enemy AI architecture, and the plan for the full roster

Epic `cmufklb100001p92xs1ey2fb1` · plan task `cmufklb4p000bp92xhnbr13y6` · written 2026-09-25 against
`agent/auto-dev` @ `3df6e1e`.

Built on `1-context.md` (codebase facts, requirements R1–R14 / L1–L21) and `2-research.md` (outside findings,
improvements I-1…I-17). Neither is re-derived here. The attached documents live in
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/` (`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` = **[IDEAS]**, `ENEMIES.md` =
**[AUDIT]**, the same text as `docs/enemy-rework/current-enemies.md`). This is phase 1 of 17. No earlier phase
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
| **P-2** ✱ | **Extend the existing `AttackController`** (`global/components/attack_controller.gd`). Do not add a second one. | It already *is* the §3.1 contract: a pattern plus a pool on a timer. Three enemies and the ally fighter use it. It needs three additions: an aim source (TargetInfo plus accuracy), a hold-fire switch the brain drives, and `fire_now()` for telegraphed shots. |
| **P-3** ✱ | §30's `MovementProfile` / `AttackProfile` / `DefenseProfile` / `TacticalProfile` become **`@export_group` sections of flat fields on each enemy's `ShipConfig` subclass**. They are not nested resources. | `test_config_instance_isolation.gd` rejects any Object/Array/Dictionary field on a config (209–227) and allows one `*config*.tres` per entity dir (107). Groups give the same at-a-glance inspector. The data stays a complete shallow copy for `privatise()`. |
| **P-4** ✱ | **`DefenseProfile` is a scene component node**, not a `Resource`. It owns the hurtbox mask and `accepted_damage_types`. Runtime armour state lives on the node. | A mutable shared resource would leak the ram ship's "armour stripped" state to every ram ship. That is the exact trap `privatise()` exists for. A node is per-instance by construction. |
| **P-5** | Armour stays a **damage rule on a full-size hurtbox**. Later armour should prefer `accepted_damage_types` plus `is_armored()` deflection over mask exclusion. The ram ship's mask toggle (33 → 97) is kept byte-identical in Phase 1 and becomes profile *data*. | The project already ruled this, and `test_enemy_hurtbox_geometry.gd` gates it. A mask-excluded bullet passes through silently; a deflected one flashes and reports. Phase 4's Ram Corvette decides whether to move to deflection. |
| **P-6** ✱ | "Name every used layer" is **five fixes, not two**: layer 3's typo (`environemnt_player` → `environment_player`), layer 5 `pickups` (all 12 pickups use it; the audit missed it), layer 6 `player_rockets`, layer 11 `hazard_contact`. **Every numeric value is unchanged.** A `CollisionLayers` constants script replaces magic numbers in the code this phase touches. | Layer names are display-only in Godot, so renaming is safe. Keeping the numbers answers the epic's open question on "numeric layer allocation". IDEAS §15's table is wrong in two places: it gives 2048 the hazard meaning 1024 already has, and it reserves 4096 for bosses. Bosses need no layer, because boss modules are ordinary enemy hurtboxes (the station's turrets prove it). No new layer is allocated until something uses it: **Phase 6** allocates `area_control` when gravity wells arrive. |
| **P-7** ✱ | The Assault constraint is a **velocity filter** between the mover's desired velocity and the single `move_and_slide()`. It has a **soft band** (edge pressure) and a **hard band** (IDEAS §34's 450 px). An enemy outside the hard band may only move *inward* until it has entered. | Every Assault spawn starts above the screen (`wave_manager.gd:175`), so a hard clamp would teleport it. This has the same shape as Godot's `NavigationAgent2D` velocity hook. Nova Drift fixed the same problem by steering fresh enemies on-screen first (`2-research.md` §2). |
| **P-8** ✱ | Phase 1 **ports the Drone Interceptor** onto the new contracts as the proof consumer. Its tuning and identity are kept, and its behaviour spec runs in both modes. | Contracts that nothing real uses drift into the wrong shape. It is the only self-driven, world-pixel enemy with prediction code, and it spawns without `.move()`. Phase 2's Razor Drone *builds on* the port. |
| **P-9** ✱ | Brains **tick on physics through one owner** (`BaseEnemy._physics_process`), with accumulated-`delta` clocks and an injectable seeded `RandomNumberGenerator`. The brain uses no `Timer` nodes. | GUT `simulate()` does not fire Timers. `StateMachine` ticks in `_process`, which is why the path mover has to disable it by name. The race AI already uses the `tick(delta)` shape (`RacerStateMachine`). |
| **P-10** ✱ | `EnemyPathMover` **suspends AI through a `suspend_ai()` contract**. The `"AIStateMachine"` name lookup stays as a fallback. | A duck-typed call, like `is_armored()` and `face_instant()`. While a path is attached, the path mover stays the only position writer, so all 264 path-driven spawns are unchanged. |
| **P-11** ✱ | `TargetInfo`'s intercept **can fail** and returns an `ok` flag. An **`accuracy` 0–1** knob blends intercept aim with direct aim. Assault patterns default to `0.0`, which is today's aim exactly. | A target faster than the shot has no intercept solution. A 100%-accurate AI is not fun. One scalar is the whole hook that Phase 16's difficulty tiers turn. |
| **P-12** ✱ | `ProjectileLifetime` is a component that **emits the host's `expired`** and never frees anything itself. Its rules are `max_time`, `max_distance` from the origin, and an optional `world_rect` supplied by the mode. `persist_after_owner_death` is **documented only** and becomes a pool policy in Phase 5 (rockets). | This keeps the one-owner rule: a pooled bullet recycles, and an unpooled sniper shot frees through its existing `expired → queue_free`. Screen visibility is deliberately not a rule, because it is camera-bound and false on the first frame. |
| **P-13** | The mode is **declared by the world, found by duck-type**. `ArenaCamera` joins the group `&"assault_arena"` and answers `enemy_movement_constraint()` and `projectile_world_rect()`. With no provider in the tree, the mode is Open Space: no constraint and no rect. Tests inject both directly. | Nothing in `global/` may import the Assault-only `ArenaCamera` class. A group plus `has_method` is the project's accepted cross-module contract. Open Space needs zero wiring, and the same enemy scene runs in both modes. |
| **P-14** | IDEAS §41's seven phases become the **17-phase chain** in §7. The three blocks §41 never slotted are placed explicitly: battlefield structures (§6.3–6.10), hazard perception (§3.2.5), and the art pass (§21–23). | Without a slot they would silently fall out of scope. The chain is already on the board. §7 fills in what each phase inherits from this one. |
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
foundation that phases 2–17 build ~10 reworked enemies, structures and bosses on:

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
| `EnemyMover` | `global/enemy_ai/enemy_mover.gd` | `Node` component, the single writer of the actor's `velocity`/`rotation` when active |
| `EnemyBrain` | `global/enemy_ai/enemy_brain.gd` | `Node` base with `tick(delta)`; concrete brains extend it |
| `MovementConstraint` | `global/enemy_ai/movement_constraint.gd` | `RefCounted` base: `filter(position, desired) -> Vector2` (identity) |
| `AssaultCorridorConstraint` | `assault/scenes/systems/assault_corridor_constraint.gd` | extends `MovementConstraint` |
| `ProjectileLifetime` | `global/components/projectile_lifetime.gd` | `Node` component |
| `AttackController` | `global/components/attack_controller.gd` | extended (§2.7) |
| `BaseEnemy` | `assault/scenes/enemies/base_enemy.gd` | refactored in place (it stays where 10 scenes and every test reference it) |
| `ArenaCamera` | `assault/scenes/systems/arena_camera.gd` | joins `&"assault_arena"`; two provider methods |
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
var actor: BaseEnemy                  # set by BaseEnemy before the first tick
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
2. Apply `max_speed` / `acceleration` limits. `acceleration = 0` means instant, which is what the port needs to
   stay exact, since today's interceptor sets velocity directly.
3. `constraint.filter(actor.global_position, v)`, if there is a constraint.
4. `actor.velocity = v; actor.move_and_slide()`.
5. Facing. **One facing rule** for every mover-driven enemy:
   `rotation = lerp_angle(rotation, heading.angle() - actor.sprite_forward_angle, delta · turn_lerp)`.
   `heading` is either the velocity or an explicit `face_toward(point)` request. `turn_lerp = 0` means instant.

`EnemyMover` exports `max_speed`, `acceleration`, `turn_lerp` and `constraint_mode` (`AUTO` | `NONE`).
- `AUTO` resolves the constraint once in `_ready()` from the `&"assault_arena"` provider (P-13).
- `mover.constraint = X` set before `add_child` wins, which is how tests inject a mode.

It never `push_error`s when parented to a non-`CharacterBody2D`. It `push_warning`s and disables itself instead,
because `test_project_load_integrity.gd` instantiates every script with zero engine errors allowed.

### 2.5 `AssaultCorridorConstraint`

```
visible = Rect2 of the Assault playfield, derived from ArenaCamera constants:
          pinned centre (640,360) ± half viewport ± (H_LIMIT, V_LIMIT)  →  x −100…1380, y −380…1100
soft    = visible grown by soft_band (120 px)        # edge pressure ramps 0→1 across this band
hard    = visible grown by hard_band (450 px, IDEAS §34)
```

`filter(pos, v)`:

1. **Not yet entered** (`pos` outside `visible`, and it has never been inside): only the component of `v`
   pointing *toward* `visible` is kept.
   - If `v` has no inward component, a minimum inward velocity is supplied (`entry_speed`, default 0.5·|v| or
     60 px/s), so a spawn can never stall outside.
   - `entered` latches true once `pos` is inside `visible`. This fixes today's wave-spawn-above-the-screen case.
2. **Entered, inside `soft`**: `v` is kept, then an inward pressure proportional to the band depth is added.
   Inside `visible` the pressure is 0.
3. **Entered, at or beyond `hard`**: outward components are removed, so the enemy slides along the edge and
   does not stall.

One constraint instance per mover. It holds the `entered` latch, so the provider returns a *new* instance each
call. The numbers (120, 450, 60) are judgement or IDEAS §34, and they are flat exports on the constraint.

**Rejected:**
- A position clamp after `move_and_slide`: it teleports spawns and desyncs velocity.
- Transforming the AI into camera space: it reintroduces exactly the coupling the epic removes.

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
and `use_world_rect := true`. Each rule is checked every physics frame.

- `reset()` records the origin and zeroes the clock. `EnemyBullet.reset()` calls it, and `BulletPool.acquire()`
  already sets `global_position` *before* `reset()` (62–76), so the origin is correct.
- The first rule that trips emits the host's `expired` **once**, through `host.expired.emit()` with a
  duck-typed `has_signal`, then latches until the next `reset()`. It never calls `queue_free`.
- **World rect:** resolved per `reset()` from the `&"assault_arena"` provider's `projectile_world_rect()`.
  `ArenaCamera` returns the derived rect **plus 64 px**, which equals today's constants exactly: x −164…1444,
  y −444…1164.
- **Race mode:** `RacerWeapon` also fires `EnemyBullet`. The task that lands this component reads the race
  scene and gives it a provider returning the same legacy rect. Race bullets then expire exactly where they do
  today, and a race regression test pins it.
- **No provider (Open Space):** only the time and distance rules apply.

`enemy_bullet.tscn` gains the node with these defaults:
- `max_time = 10 s`, `max_distance = 2400 px`. Both are chosen so neither rule can trip *inside* today's rect:
  the rect diagonal is about 2274 px, and the slowest enemy bullet is about 250 px/s, so it takes about 9.1 s.
  That means the Assault expiry point is unchanged. The test states this derivation.
- `enemy_bullet.gd:12-16` and the constants go.
- The sniper shot (`enemy_sniper_bullet.tscn`, same script, unpooled) inherits it and still frees through its
  `expired → queue_free`.

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
  damage/death hooks, the contract subclasses (the space station) override. Their stale line references in
  `space_station.gd:184`, `station_turret.gd:31` and `space_station/ENEMY.md:475` are fixed.
- `suspend_ai()`: sets `_ai_suspended`, calls `_brain.on_suspended()`, and zeroes `velocity`. It is idempotent.
  `EnemyPathMover._ready()` calls `_actor.suspend_ai()` if `has_method`. It keeps
  `set_physics_process(false)` and the `"AIStateMachine"` fallback (light assault ship), so every existing
  enemy is suspended exactly as today.
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
- **Dash end, Assault:** the exact legacy cull (camera `global_position ± viewport/2 ± 80`, which ignores
  `cam.offset`) moves to `AssaultCorridorConstraint.is_past_cull(pos)`. That keeps today's quirk identical.
- **Dash end, Open Space:** there is no cull today, so the drone would dash forever. New flat config field
  `dash_max_distance = 1600` px, a judgement value. After that distance the drone frees itself. It is a one-way
  kamikaze, and leash/return is Phase 13's.
- **Station reinforcements** spawn it as a self-driven ship (`test_station_reinforcements.gd:325`). That test
  stays green unchanged.

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
   flow, `died` then free, scoring fields copied from config, and the `AnimatedSprite2D` 180° flip.
2. **[t2-pin-path-mover]** Characterise `EnemyPathMover`: sample × `WORLD_SCALE` offset from the spawn point,
   actor physics suspended, `AIStateMachine` disabled, both exit modes, the off-screen cull (80 px margin,
   never-on-screen actor not culled), the no-camera warning path, and nose-down facing.
3. **[t3-pin-drones]** Characterise PatrolDrone (drift, scene-wired damage, `died` + free, mask 64 and the
   rocket immunity, body layer 256) and the Drone Interceptor (ENTER→ORBIT at the radius, orbit speed clamp,
   dash direction = predicted position, dash speed, contact kill, facing), with the RNG pinned by
   `seed()`-ing the global RNG *in the test*.
4. **[t4-layers]** Name layers 3/5/6/11, add `CollisionLayers`, and add the invariant test
   `test_collision_layer_names.gd`.
5. **[t5-defense-profile]** `DefenseProfile`; BaseEnemy default profile; ram ship and station turret onto it.
   Step 1's pins stay green unchanged.
6. **[t6-base-enemy-debt]** Verbose-gated death print, `sprite_forward_angle`, documented virtual hooks and
   stale refs, `ShipConfig` export groups.
7. **[t7-target-info]** `TargetInfo`, with unit tests.
8. **[t8-attack-controller]** `AttackController` extension, and `accuracy` on the aimed and gatling patterns.
9. **[t9-steering]** `Steering` primitives, with unit tests.
10. **[t10-brain-mover]** `EnemyBrain`, `EnemyMover`, `MovementConstraint`, the BaseEnemy tick loop,
    `suspend_ai()`, the path mover's duck-typed suspension, and a test fixture enemy.
11. **[t11-corridor]** `AssaultCorridorConstraint` and the ArenaCamera provider.
12. **[t12-dual-harness]** The dual-mode harness helper, and the fixture behaviour spec in both modes.
13. **[t13-projectile-lifetime]** `ProjectileLifetime`, the EnemyBullet migration, the race provider, and
    regression tests.
14. **[t14-port-interceptor]** Port the Drone Interceptor, and its behaviour spec in both modes.
15. **[t15-docs]** Docs pass (`updating-project-docs`) and the phase's *as built* notes.

Parallelism: the t1–t3 pins, t4, t7 and t13 are independent of each other.

---

## 4. Test plan

All tests are GUT, deterministic, and use `simulate(node, n, 1.0/60.0)` or direct `tick()`/`step()` calls. No
test awaits a `Timer`. Fixtures live under `tests/helpers/` (never named `test_*`). Any new `await` is followed by
`scripts/check-test-leaks.sh`.

| File | Kind | Cases (at least one boundary each) |
|---|---|---|
| `tests/integration/test_base_enemy.gd` | characterization, then intent for the new hooks | Mask per roster enemy equals the pinned value (a roster sweep over `assault/scenes/enemies/*/*.tscn`, so a new enemy is covered); the ram mask goes 33 → 97 on its first received hit (a rocket or environment hit, since 33 excludes bullets) and never goes back; lethal damage → `died` emitted once, `was_killed`, freed; non-lethal → no `died`; scoring copied from config; `AnimatedSprite2D` rotation 180; **boundary:** an enemy with a scene `DefenseProfile` is not given a second one; **boundary:** death print absent without `--verbose` (asserted structurally: the `print` is inside an `is_stdout_verbose()` branch, same approach as the signal-arity sweep) |
| `tests/integration/test_enemy_path_mover.gd` | characterization | Position = spawn + sample(t)·2.0 after N frames; actor `is_physics_processing()` false; `AIStateMachine` disabled; `suspend_ai()` called when present (after t10); FREE_ON_DURATION frees at `exit_time` and at `total_duration()` when 0; **boundary:** an actor spawned off-screen and never entering is not culled; an actor that entered then left by more than 80 px is culled; exactly 80 px is not |
| `tests/integration/test_patrol_drone.gd` | characterization | Drifts `initial_direction·move_speed`; zero direction → RIGHT; a scene-wired HitBox overlap decreases health; health 0 → `died` + freed; **characterization of a bug:** HurtBox mask == 64 (rockets pass through), body layer 256 |
| `tests/integration/test_drone_interceptor.gd` | characterization *before* the port, **the port's acceptance test after it** | No player → zero velocity; ENTER velocity = approach_speed toward the player; enters ORBIT at ≤ orbit_radius (**boundary:** exactly the radius); orbit correction speed clamped to [60, orbit_correct_speed]; the dash starts when the timer expires; the dash direction uses `player.velocity·0.2`; dash speed 480; contact → health 0; facing converges to nose-up toward the player |
| `tests/unit/test_target_info.gd` | intent | No target → `has_target` false, `aim_direction` DOWN; `predicted_position(0)` = position; stationary target → intercept ok, time = dist/speed; **boundary:** a target moving away faster than the shot → `ok = false`, point = position; `shot_speed = 0` → not ok; a target at the shooter's position → ok, time 0, no NaN; accuracy 0 = direct, 1 = intercept, 0.5 = midpoint; a target freed after the snapshot → reading members is safe |
| `tests/unit/test_steering.gd` | intent | Each primitive's direction and magnitude; `arrive` → speed 0 at the target and full speed outside the derived radius; `orbit` anchor and clamp match the interceptor formula; `strafe` ⟂ the target line for both `side` values; `hold_position` is zero inside the tolerance; **boundary:** zero vectors or a coincident target never return NaN |
| `tests/unit/test_enemy_mover.gd` | intent | Accel limit caps the velocity change per step; `acceleration = 0` is instant; max_speed truncates; the constraint filter is applied; the facing rule with `sprite_forward_angle` ±PI/2; `boost` overrides for `duration` and then ends; **boundary:** not a CharacterBody2D parent → warning, disabled, no error |
| `tests/unit/test_assault_corridor_constraint.gd` | intent | Inside visible → identity; soft band → inward pressure grows with depth; beyond hard → no outward component, tangential kept (slides, never stalls); **boundary:** spawned above the screen with outward intent → a strictly inward velocity until entered, then the latch holds; derived rect == ArenaCamera constants |
| `tests/integration/test_enemy_brain_contract.gd` | intent | The BaseEnemy loop ticks brain then mover once per physics frame; `suspend_ai()` stops both and zeroes velocity; `EnemyPathMover` attached → brain suspended and path position exact; the rng is seedable (same seed → same sequence); an enemy without a brain → the base loop is inert (the legacy subclass path is unchanged) |
| `tests/integration/test_enemy_dual_mode.gd` | intent (IDEAS §40) | `use_parameters([open_space, assault])` over the fixture and the ported interceptor: reaches orbit; holds the radius within tolerance *or* stays inside the soft band when clamped; the dash direction is identical in both modes for the same seed and positions; the assault harness spawn above the screen enters; the open_space interceptor frees after `dash_max_distance` |
| `tests/unit/test_projectile_lifetime.gd` + `tests/integration/test_enemy_bullet_lifetime.gd` | intent + regression | Each rule trips alone; `expired` fires exactly once per life and never `queue_free`s (checked via `BulletPool.acquire()` reuse, not `_idle.size()`, per the player-bullet-lifetime precedent); `reset()` re-arms; **boundary:** a bullet at x = 1444 lives and at 1444.1 expires with the Assault provider; with no provider the same position lives; the 10 s / 2400 px defaults cannot trip before the rect for the slowest shipped enemy bullet speed (derived from the shipped patterns, not hardcoded); the race bullet still expires at the legacy rect; the unpooled sniper shot is freed |
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
| Two position writers (path mover + mover) | The path mover calls `suspend_ai()` *and* keeps `set_physics_process(false)`, belt and braces; pinned in t2 and t10. |
| The mask regresses for one enemy | t1 pins every roster mask *before* t5 touches line 51. |
| The race breaks from the EnemyBullet change | The race provider plus a race regression test in t13. |
| The port changes feel | t3 pins the numbers before t14; `acceleration = 0`; the same config. The playtest feel is a human eyeball item in the dossier. |
| `test_project_load_integrity` fails on new components | Components warn, never error, when instantiated bare; the fixture enemy lives under `tests/helpers/`. |
| New `class_name`s collide | Names were checked against the project: `MovementController` is taken (hence `EnemyMover`); `TargetInfo`, `Steering`, `EnemyBrain`, `DefenseProfile`, `ProjectileLifetime`, `CollisionLayers` and `MovementConstraint` are free today. The implementer re-greps before adding. |
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

---

## 7. Roadmap: the full idea split into the 17-phase chain

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

---

## 8. Requirements coverage

Every Phase 1 requirement maps to task keys. Everything else maps to the phase that owns it. Nothing is dropped.

| Requirement (source) | Delivered by |
|---|---|
| R1 mode-neutral BaseEnemy (IDEAS §41.1) | t5, t6, t10 (the file move is Phase 15) |
| R2 brain / mover / attack / defense contracts (§3.1) | t10 (brain, mover), t8 (attack), t5 (defense) |
| R3 movement primitives (§3.2) | t9, t10 (seek, arrive, orbit, intercept, evade/retreat_from, strafe, hold_position, drift, boost). Others: spiral/corkscrew/formation_slot → Ph2; lead_target → Ph3; break_contact → Ph4; regroup → Ph14 |
| R4 Assault constraint (§1.3, §34) | t11, t12 |
| R5 world-aware projectile lifetime (§12) | t13; `persist_after_owner_death` documented in t13, built in Ph5; `max_distance_from_player` → Ph13 (needs encounter ownership) |
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
| L1 hazards (§3.2.5, §18.6) | Ph6 |
| L2 persistence (§3.3, §33) | Ph13 |
| L3 shared combat states (§4) | vocabulary documented in t10; used from Ph2 |
| L4 Swarm, Razor, Fighter, Gatling | Ph2, Ph3 |
| L5 Bomber, Sniper, Ram, Missile, Support | Ph4, Ph5 |
| L6 structures (§6.3–6.10) | Ph6–Ph9 |
| L7 Heavy Gunship, Carrier | Ph10 |
| L8 bosses (§8–10, §24–26) | Ph11, Ph12 (and Ph10 for §26) |
| L9 weapon families (§11) | Ph3 bullets, Ph5 rockets, Ph8 energy, Ph7/Ph9 area control |
| L10 armour / shields / weak points / modules (§13–14) | Ph4 armour, Ph5 shields, Ph10 modules and weak points |
| L11 contact-damage profiles (§16) | Ph2 (None/Collision/Ramming), Ph4 (Armour), Ph7 (Explosive) |
| L12 dynamic formations and squad messages (§17, §18, §35) | Ph2 (roles), Ph14 (messages, regroup), Ph15 (spawn layouts) |
| L13 idle profiles (§18.5) | Ph14 |
| L14 EncounterDirector (§19, §32) | Ph13 |
| L15 Assault migration (§20, §34–35) | Ph15 |
| L16 readability art (§21–23) | each roster phase; audit in Ph17 |
| L17 line of sight (§28) | Ph4 |
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
| Path mover coexistence | `suspend_ai()` plus the name fallback (P-10). |
| DefenseProfile shape | A node (P-4). |
| A real consumer or a fixture | Both: the interceptor plus a `tests/helpers/` fixture (P-8). |
| PatrolDrone's rocket immunity | Pinned, not fixed (P-16). |
| How the mode is known | The `&"assault_arena"` duck-typed provider (P-13). |
