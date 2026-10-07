# Decision log — Enemy rework (idea cmufkkgmx0001o02y6bnf52bq)

Running log shared by every phase epic of this idea. Each phase appends; nothing earlier is rewritten.
Where a phase's *as built* section disagrees with its plan section, the *as built* section wins.

## Phase 1 - Enemy rework, phase 1: mode-neutral enemy AI architecture and plan for the full roster (2026-09-25)

Plan: `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md`, with research in `1-context.md` and `2-research.md` in
the same directory (revision 2, after plan review round 1 — `4-review.md`). The 19-phase roadmap is in §7 of the plan, and the requirement → phase coverage table is in §8.
These are *planned* decisions; check this phase's `as built` section, once written, before relying on them.

### Names and places (later phases build on these)
- `EnemyMover` (`global/enemy_ai/enemy_mover.gd`) is the enemy movement component.
  - **Never `MovementController`.** That name is the player's input handler.
  - When active, it is the **single writer** of an AI enemy's `velocity` and `rotation`, and it performs the one
    `move_and_slide()`.
  - Exports `max_speed`, `acceleration`, `braking` (0 = same as acceleration), `turn_lerp`, `max_turn_rate`
    (rad/s, 0 = off; IDEAS §3.1 `turn_rate`) and `constraint_mode` (`AUTO` | `NONE`).
  - Reads the actor's `sprite_forward_angle` duck-typed (default `PI/2`); nothing in `global/enemy_ai/` is typed
    against `BaseEnemy`.
  - Gated by `tests/integration/test_enemy_mover_single_writer.gd`: brains, `global/enemy_ai/*` and the root
    script of any enemy scene with an `EnemyMover` must not assign `velocity`/`rotation` or call
    `move_and_slide()`. Empty permanent allowlist.
- `EnemyBrain` (`global/enemy_ai/enemy_brain.gd`) exposes `tick(delta)`, `on_suspended()`, `actor`
  (typed `CharacterBody2D`), `mover`, `attack` and `rng`.
  - `rng` is a seedable `RandomNumberGenerator` (the `rng_seed` export).
  - Concrete brains extend it and live beside their enemy, e.g. `drone_interceptor_brain.gd`.
- `Steering` (`global/enemy_ai/steering.gd`) holds pure static primitives that return a desired velocity:
  seek, arrive, orbit, intercept, evade, retreat_from, strafe, hold_position and drift.
  - `boost` is stateful and lives on `EnemyMover`.
  - Deferred to later phases: `spiral`/`corkscrew`/`formation_slot` → Ph2, `lead_target` → Ph3 (it is
    `TargetInfo.aim_direction`), `break_contact` → Ph4, `regroup` → Ph14.
- `MovementConstraint` (`global/enemy_ai/movement_constraint.gd`) is the identity `filter(pos, desired) -> Vector2`.
  - `AssaultCorridorConstraint` (`assault/scenes/systems/`) extends it. It filters **per axis**, speeds in px/s:
    not yet entered → inward only, at least `entry_speed` 60, other axis free, hard band not applied until the
    "entered" latch; soft band (0–120 px) → outward kept + pressure `edge_pressure·d/120` (`edge_pressure` 200);
    outer band (120–450 px) → full pressure, outward scaled to 0 at 450; beyond 450 → outward removed + full
    pressure ("forced to re-enter"). Tangential motion is always kept.
- `EnemyWorld` (`global/enemy_ai/enemy_world.gd`, static) is the **only** lookup of the mode provider:
  `arena(tree)`, `projectile_world_rect(tree)`, `cull_rect(tree)`, `movement_constraint(tree)`, all duck-typed.
- `TargetInfo` (`global/enemy_ai/target_info.gd`, RefCounted snapshot) is the **only** way new code finds or
  predicts the player.
  - `TargetInfo.player(tree)` is the resolver. `intercept()` returns `{ok, point, time}` and can fail.
  - `aim_direction(from, shot_speed, accuracy)` is the aim entry point. The `accuracy` range is 0..1, and 0 means
    aim straight at the target, as enemies do today.
  - `line_of_sight()` is a stub until Ph4.
- `DefenseProfile` (`global/components/defense_profile.gd`) is a **Node, not a Resource**. It owns the hurtbox
  mask and `accepted_damage_types`.
  - Runtime armour state lives on the node.
  - BaseEnemy creates a default profile (mask 1121) when the scene has none.
  - Phase 1 supports only a one-way alternate mask, which is what the ram ship needs. Multi-state armour is Ph4's.
- `ProjectileLifetime` (`global/components/projectile_lifetime.gd`) has `max_time`, `max_distance` and
  `use_world_rect` rules.
  - It emits the host's `expired` once and **never frees**, which preserves the one-owner rule. `expire_now()` is
    IDEAS §12's `explicit_destroy()`.
  - It **arms lazily**: on `reset()` or its first physics tick, whichever comes first, never in `_ready()` —
    because unpooled projectiles (the sniper shot) are never `reset()`.
  - `max_distance` is measured from the origin, not the owner (owner distance → Ph5).
  - `EnemyBullet` defaults are **derived**: `max_distance = ceil_to_100(diag + 64) = 2400 px`,
    `max_time = ceil(diag / min_speed) + 2 s = 18 s`, with `diag ≈ 2274 px` (legacy rect) and `min_speed = 150`
    over every shipped enemy-bullet speed source (table in plan §2.9). A new, slower bullet must be added to the
    source list in `test_enemy_bullet_lifetime.gd`, and the defaults re-derived.
  - `persist_after_owner_death` is documented only. It becomes a `BulletPool` policy in Ph5.
- `CollisionLayers` (`global/physics/collision_layers.gd`) holds the named constants. The layer names are:
  `environment` 1, `environment_interactable` 2, `environment_player` 4 (typo fixed), `pickups` 16,
  `player_rockets` 32, `player_hitbox` 64, `player_hurtbox` 128, `enemy_hitbox` 256, `enemy_hurtbox` 512,
  `hazard_contact` 1024.
  - **No numeric value changed.**
  - No new layer is allocated until something uses it. Ph6 allocates `area_control` (bit 12, 2048), IDEAS §15's
    "area-control / special hazards" meaning.
  - Bosses get no layer of their own; their modules are ordinary enemy hurtboxes.

### Conventions
- **How the mode is detected:** the world declares it. `ArenaCamera` joins the group `&"assault_arena"` and answers
  `projectile_world_rect()` (today's EnemyBullet bounds, x −164…1444, y −444…1164), `enemy_cull_rect()` (the Drone
  Interceptor's legacy camera ± viewport/2 ± 80 cull) and `enemy_movement_constraint()` (a new instance per call).
  - Because the race scene's camera is an `ArenaCamera`, the race is an Assault arena with no extra wiring.
    `level_2.tscn` (plain `Camera2D`, unreferenced) is not.
  - With no provider, the mode is Open Space: no constraint and no rect.
  - Nothing under `global/` may reference the `ArenaCamera` class.
  - Tests inject the constraint or rect directly.
- **Brain ticking:** brains tick on **physics**, from `BaseEnemy._physics_process`, in the order `brain.tick` then
  `mover.step`.
  - Clocks are accumulated `delta` values. There are no `Timer` nodes, and randomness comes only from `brain.rng`.
  - Legacy subclasses that define their own `_physics_process` are untouched.
- **Rails:** `EnemyPathMover` suspends AI by calling `suspend_ai()` **in addition to** `set_physics_process(false)`
  and the `"AIStateMachine"` name lookup, all three unconditionally. The lookup is not a fallback: the light
  assault ship is a `BaseEnemy` whose state machine moves it from `_process`, and only the lookup stops that.
  Pinned on the real `light_assault_ship.tscn`. The lookup retires in Ph15.
  - While a path is attached, the path mover remains the only position writer.
  - Rail-driven waves stay unchanged until Ph15.
- **Facing:** there is one rule for mover-driven enemies:
  `rotation = heading.angle() - sprite_forward_angle`.
  - `sprite_forward_angle` is a BaseEnemy export. The default is `PI/2` (art nose-down); nose-up art uses `-PI/2`.
  - `_rotate_sprite()`'s 180° child-`AnimatedSprite2D` flip is kept as art correction.
- **Config grouping:** IDEAS §30 "profiles" are `@export_group` sections of **flat** fields on each `ShipConfig`
  subclass.
  - The groups are Movement / Attack / Defense / Tactics / Scoring.
  - Configs never hold nested resources, arrays or dictionaries; `test_config_instance_isolation` enforces this.
- **AttackController:** there is one `AttackController`, extended with `enabled` (hold fire), `driven_by_brain`
  (the brain calls `tick(delta)`) and `fire_now()`. Aimed and gatling patterns expose `accuracy` (default 0).
- **Dual-mode tests:** every reworked enemy's behaviour spec runs in the `open_space` and `assault` harnesses
  (`tests/helpers/`, `test_enemy_dual_mode.gd`, `use_parameters`). Assertions are stated relative to the constraint.
- **Proof consumer:** the Drone Interceptor is ported to be driven by `DroneInterceptorBrain` + `EnemyMover`,
  with acceleration 0 so its feel is unchanged.
  - New flat config field `dash_max_distance` (1600 px) is its Open Space dash end.
  - It runs with `constraint_mode = NONE` in Phase 1, so it is 1:1 with today in Assault. **Ph2 (Razor Drone)
    turns the corridor on** and must re-pin its edge behaviour.
  - In Assault it keeps the legacy camera cull via the provider's `enemy_cull_rect()`.
  - Its only live spawns are level 1's two (`level_1_director.gd:290-291`); the station reinforcements never use it.
  - Ph2's Razor Drone evolves this port rather than replacing it.

### Deliberately deferred
| Item | Deferred to | Reason |
|---|---|---|
| `DamageReaction` replacing BaseEnemy's damage flow | Ph5 | Revisit when enemies first need shields. Until then, `_on_received_damage` / `_on_health_changed` are documented virtual hooks. |
| `BulletPool`'s grandparent container (make it injectable) | Ph2 | Ph2 is the first phase to fire enemy weapons in Open Space. |
| PatrolDrone | Ph2 | It is characterised, not fixed: rocket-immune (mask 64) and body on layer 256. The Swarm Drone replaces it. |
| Real line-of-sight | Ph4 | |
| Ram armour as deflection vs mask | Ph4 | |
| `bomb.gd` lifetime | Ph4 | |
| Sniper `FLY_IN_TIME` coupling | Ph4 | |
| Context steering and hazards | Ph6 | |
| `max_distance_from_player` lifetime | Ph13 | |
| Leash / search | Ph13 | |
| Difficulty tiers | Ph16 | Only the `accuracy` hook exists. |
| Moving `BaseEnemy` to `global/` | Ph15 | |
| The corridor on the Drone Interceptor / Razor Drone | Ph2 | Kept off in Phase 1 so the port is 1:1. |
| Retiring the path mover's `"AIStateMachine"` name lookup | Ph15 | Needs the light assault ship on a brain first. |
| `max_distance_from_owner` lifetime | Ph5 | With owner-bound projectiles and `persist_after_owner_death`. |
| Stale `base_enemy.gd:<line>` citations | this phase, t15 | Fixed once as a repo-wide sweep citing symbols. |
| Retiring `EnemyPathMover` as the default | Ph15 | |

### Built in t10-brain-mover (2026-09-25) — details later phases depend on
- `EnemyMover` requests are **per step**: `request_velocity()` / nudges / `face_toward()` clear after every `step()`,
  so a brain must request every tick (a brain that stops requesting brakes to zero). All limits default to 0
  (off/instant), including `max_speed` (0 = uncapped). `boost()` ignores requests, nudges, `max_speed` and the
  accel/braking limits, but not the constraint. `halt()` is the sanctioned velocity zeroing (used by `suspend_ai()`).
- `arrive()` / `hold_position()` wrappers size the slowing radius with the mover's **deceleration**
  (`braking`, else `acceleration`), not `acceleration`.
- `BaseEnemy` API: `suspend_ai()` (idempotent), `is_ai_suspended()`; `_brain` / `_mover` are resolved by type.
  `EnemyBrain` resolves `actor` / `mover` / `attack` in its own `_ready()` — concrete brains that override
  `_ready()` must call `super._ready()`.
- **Phase 15:** a rail suspends the brain, so a `driven_by_brain = true` `AttackController` **stops firing** on a
  path-driven spawn (the brain no longer ticks it). Timer-driven (`_process`) controllers keep firing as today.
  Phase 15's migration must decide who ticks fire on a rail.
- The single-writer gate is stricter than planned: it also forbids `velocity.x/.y` writes, `look_at(` / `rotate(`,
  `set_velocity(` / `set_rotation(` and `move_and_collide(`, and sweeps the mover-driven root script's **ancestors**
  (so `base_enemy.gd` must never write `velocity`/`rotation` either). Test fixture: `tests/helpers/fixture_enemy.tscn`.

### Built in t12-dual-harness (2026-09-25) — details t14 depends on
- `tests/helpers/enemy_ai_harness.gd` (no `class_name`, preload it) exposes `open_space()` and `assault()`,
  each returning a `RefCounted` with `root: Node2D`, `player: CharacterBody2D` (already in group `"player"`)
  and `is_assault: bool`. `assault()`'s `root` also holds a bare `ArenaCamera`, so an `AUTO` `EnemyMover` under
  it resolves `AssaultCorridorConstraint` through `EnemyWorld`, the same lookup the real game uses.
  `open_space()`'s `root` holds no provider. The caller adds `root` to the tree itself
  (`add_child_autofree(harness.root)`) before parenting anything under it.
- **A real GUT footgun the harness's shape forces on every caller, including t14:** `use_parameters([...])` is a
  default-argument expression, and GDScript re-evaluates a default argument's expression on **every** call, not
  just the first — `use_parameters()` itself only *uses* the first call's array, but every later call still
  builds (and immediately abandons) a fresh one. `HARNESS.open_space()` / `HARNESS.assault()` build a `Node2D`
  subtree, and a `Node` is not ref-counted, so an abandoned one is a genuine, silent leak (`scripts/
  check-test-leaks.sh` catches it: `ObjectDB instances leaked` / `resources still in use` at process exit).
  **Never write `use_parameters([HARNESS.open_space(), HARNESS.assault()])`.** Parameterize on a bare label
  instead and build the harness from it inside the test body:
  `func test_x(mode: String = use_parameters(["open_space", "assault"])) -> void:` then
  `var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()`. `test_enemy_dual_mode.gd`
  follows this shape throughout; t14 adding the interceptor's case to the same file must too.
- `test_enemy_dual_mode.gd`'s `_tick(entity, delta)` helper is the one way this file (and t14's addition to it)
  should drive a mover-owned `CharacterBody2D` for many manual ticks: it calls `entity._physics_process(delta)`
  then overwrites `entity.global_position` with `before + entity.velocity * delta`, discarding whatever
  `move_and_slide()` actually displaced it by. `move_and_slide()` reads `get_physics_process_delta_time()`
  internally rather than the passed-in `delta`, and that value is not reliable when driven by hand outside a
  real physics substep (`test_drone_interceptor.gd`'s harness notes already flagged this) — confirmed again
  here: the corridor-entry case passed standalone and failed inside the full 845-test suite before `_tick()`
  was added, purely from that drift between runs. `velocity` itself is exact regardless (`EnemyMover` assigns
  it directly, before `move_and_slide` ever runs), so re-deriving position from it removes the dependency
  entirely.
- The orbit spec (`test_orbit_behaviour_matches_the_constraint`) deliberately orbits around the corridor's dead
  centre (640, 360) with a small radius, so the Assault run's constraint never actually engages — it proves the
  identical spec produces the identical held orbit in both modes. It does **not** exercise the "or stays inside
  the soft band when clamped" branch of the row's own assertion; that branch exists for t14's ported
  interceptor, whose real orbit sits near a corridor edge. The separate
  `test_assault_harness_above_screen_spawn_enters_the_corridor` case is what exercises the constraint while it
  is actively clamping in this phase.

## Phase 1 - as built (2026-09-27)

All 15 build-sequence tasks (t1–t15) landed on `agent/auto-dev`, plus the plan/research/review
preparation tasks. This closes the epic. `docs/epics-done/cmufklb100001p92xs1ey2fb1/` has the full
dossier (PRD/SOURCES/REPORT); this section is the short version later phases should read first.

### What was actually built

Everything the "Names and places" and "Conventions" tables above describe as *planned* landed
**as specified**, with no code-level deviation found while writing this section against the final
source: `global/enemy_ai/` (`enemy_brain.gd`, `enemy_mover.gd`, `steering.gd`, `target_info.gd`,
`movement_constraint.gd`, `enemy_world.gd`), `global/components/defense_profile.gd` and
`projectile_lifetime.gd`, `global/physics/collision_layers.gd`, `assault/scenes/systems/
assault_corridor_constraint.gd`, `ArenaCamera`'s three provider methods and its `&"assault_arena"`
group membership (joined **before** its early return, per the plan's N5), and the Drone
Interceptor's port onto `DroneInterceptorBrain` + `EnemyMover` with `constraint_mode = NONE`. The
"Built in t10-brain-mover" and "Built in t12-dual-harness" notes above, written during
implementation, are still accurate and are not repeated here.

`EnemyPathMover` suspends AI through all three unconditional steps the plan required (F3):
`set_physics_process(false)`, the `"AIStateMachine"` name lookup, and `_actor.suspend_ai()` when
present — pinned on the real `light_assault_ship.tscn`, not just a bare test fixture.
`ProjectileLifetime` arms lazily (F1) and the sniper's unpooled shot carries its own instance
(N1's fix) rather than trying to "inherit" one from a non-inherited scene. `EnemyBullet`'s derived
defaults are `max_time = 18 s`, `max_distance = 2400 px` (F2's corrected derivation), matching what
ships in `enemy_bullet.tscn` / `enemy_sniper_bullet.tscn` today.

### Deviations from `3-plan.md`

None material. The plan's own revision 2 already absorbed every round-1 review finding (F1–F11)
before implementation started, so no further deviation surfaced during the build that a later
phase needs to know about beyond what "Built in t10"/"Built in t12" above already record (the
`Engine.get_physics_frames()` tick-counting fix, the sweep blanking string literals as well as
comments, and the GUT default-argument-leak trap in the dual-mode harness).

**This docs task (t15) made one scoping call the plan's own review had already approved (N3):**
the repo-wide `grep -rn "base_enemy.gd:[0-9]"` sweep excludes `docs/plans/`, `docs/epics-done/`,
`docs/ideas/` and `docs/enemy-rework/` — historical plan/review records, finished-epic dossiers,
and the owner's own attached audit documents, none of which this phase may rewrite. Within that
scope the actual hit list differed slightly from `3-plan.md`'s "known hits today": `station_turret.gd:31`
had already been cleaned up by an earlier task (t5/t6), and two hits the plan missed —
`station_reinforcements.gd:128` and `test_station_incoming_damage_paths.gd:17` — were found and
fixed alongside the eight the plan named. All ten were rewritten to cite the symbol
(`BaseEnemy._on_health_changed`, `BaseEnemy.died`, `BaseEnemy.hurt_box`, or the `DefenseProfile`
call that now owns the mask write) rather than a line number; no test assertion changed.

### Gaps left for later phases

Everything in the "Deliberately deferred" table above still stands — nothing in this docs pass
closed any of it. In particular, for the phases that read this section next:

- **Phase 2 (Razor Drone)** turns the Assault corridor on for a ported-style enemy for the first
  time and must re-pin the Drone Interceptor's edge behaviour if it evolves the same port; it also
  owns `PatrolDrone`'s replacement and `BulletPool`'s grandparent-container assumption.
- **Phase 4** owns real line-of-sight (`TargetInfo.line_of_sight()` is still a stub), armour as
  deflection vs. mask exclusion, and the sniper's `FLY_IN_TIME` coupling.
- **Phase 15** owns retiring `EnemyPathMover`'s `"AIStateMachine"` name-lookup fallback (once the
  light assault ship moves onto a brain) and moving `BaseEnemy` itself into `global/`.
- **Phase 16** owns difficulty tiers; only the `accuracy` hook on `TargetInfo.aim_direction` /
  the aimed and gatling patterns exists today, and every shipped pattern still defaults it to `0.0`.
- No numeric collision-layer bit changed meaning or value in this phase; bit 4 (value 8) remains
  unnamed and unallocated, and bit 12 (`area_control`, 2048) is reserved for Phase 6.

## Phase 2 - Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles (2026-09-27)

Plan: `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` (**revision 2**, after review round 1). Research: `1-context.md`
and `2-research.md` in the same directory. Tasks: `tasks.json` (20 tasks, t1–t17 with t8 split into t8a–t8d). These
are *planned* decisions. Once this phase's *as built* section exists, check it first.

### Changes to Phase 1 decisions (stated in plan §2.0)
- **Explosive collision** is built in Ph2, not Ph7. Its consumer is the Swarm Drone. Ph7 (mines) reuses `ContactProfile`
  and `ContactBlast`.
- **The generic anchor-idle → combat handover (`AnchorIdle`), the Razor idle and the Swarm squad's hub idle** are built
  in Ph2. Idle profiles for other families stay in Ph14 and must use `AnchorIdle`.
- **Assault migration:** only level 1's Kamikaze/Interceptor spawns go off rails in Ph2. Every other level-1 spawn, and
  the station's two BOTTOM drones, stay on rails until Ph15.
- **`BulletPool` injectable container (P-18): not done.** Every real parent chain satisfies pool → ship → container.
  A hub test pins the Razor's pulse landing in `EnemyContainer`. This is reopened for Ph5 (owner-bound projectiles).
- **Drone Interceptor "1:1" pins are retired.** It becomes the Razor Drone with `constraint_mode = AUTO` and a non-zero
  acceleration and braking. `dash_max_distance` is removed, because the Razor survives its dash.
- **The Assault AI exit rule** frees a *live* AI enemy outside `EnemyWorld.projectile_world_rect()`, not `cull_rect()`.
  `cull_rect()` ignores the camera `offset`, so it could free a visible enemy. `cull_rect()` stays for legacy users.
- **`EnemyMover.max_turn_rate` only turns the sprite.** Phase 1 did not say otherwise, but `1-context.md` assumed it
  bends the path; it does not (`step()` sets velocity by `move_toward`). **A curved path is always a brain-side
  request** built with `Steering.turn_toward()` from the actor's *current* velocity each tick. Later phases (fighter
  turn-backs, Ram Corvette wide turn, Dreadnought arcs) must use this, not the mover's turn cap.

### Names and places (later phases build on these)
- **`ContactProfile`** (`global/components/contact_profile.gd`) is a `Node` that mirrors `DefenseProfile`. `BaseEnemy`
  resolves a scene-authored one or creates a default `COLLISION` one.
  - `enum Mode { NONE, COLLISION, RAMMING, EXPLOSIVE }`. `setup(actor, hit_box, health)`.
  - It has `set_armed(bool)`, `is_armed()` and `detonate()`, and the signals `contact_made(area: Area2D)` and
    `detonated(position: Vector2)`.
  - The `ContactHitBox` damage is always `config.collision_damage`. RAMMING and EXPLOSIVE switch the hitbox on only
    while armed (deferred `monitorable`/`monitoring`).
  - EXPLOSIVE fires on contact while armed and on death while armed, never on death while unarmed.
  - `BaseEnemy.suspend_ai()` arms the profile, so rail-driven rammers hurt on contact.
  - **Armour collision is Ph4's** new mode on the same enum.
- **`ContactBlast`** (`global/components/contact_blast.gd`, `extends HitBox`) is the explosive blast. **A blast is never
  a child of the thing that dies**: `ContactBlast.spawn(container, at, radius, damage, frames)` adds it to the owner's
  parent with a deferred `add_child` (safe inside a physics callback), places it in `_enter_tree`, keeps it monitorable
  for `frames` physics frames (≥ 2, default 3) on its own counter (never `create_timer`), then frees it. Layer 256,
  mask 0, CONTACT. Blasts do not hit enemies: enemy friendly fire is undecided. Ph4–Ph7 explosive ordnance (bombs,
  mines, rockets) should reuse it rather than `bomb.gd`'s timer-based blast.
- **`SquadController`** (`global/enemy_ai/squad_controller.gd`) is a `RefCounted` role board. It is **event-driven, with
  no clock and no motion**.
  - `enum Role { NONE, LEAD, FLANK_LEFT, FLANK_RIGHT, REAR }` and `enum Side { LEFT, RIGHT, FRONT, BACK }` (relative to
    the target's heading).
  - It has `join`, `leave`, `role_of`, `members`, `rear_index`, `claim_side`/`release_side`, `release_lead`,
    `update_target(position, heading)`, `set_engaged(member, on)`/`is_engaged()` and `attack_window_open`, and the
    signal `role_changed(member: Node, role: int)`.
  - Membership is weak, and **members hold the only strong reference**, so the board dies with its last member.
    Anything else that keeps a board (the `WaveManager`) keeps only a `WeakRef`.
  - Brains read it through a duck-typed `actor.squad` property; `null` means a squad of one. `EnemyBrain` itself is
    unchanged.
  - Ph3 fighters reuse it; Ph14 adds messages on top of it. **Engagement is shared state, not a message bus.**
- **Squads from spawns:**
  - `WaveBuilder.SpawnConfig.squad(id: StringName)` → `SpawnEntryResource.squad_id`.
  - A `formation()` is automatically one squad.
  - `WaveManager` writes a squad *key* string into each spawn dict and resolves it at spawn time through a
    key → `WeakRef` map, then sets `entity.squad` before `add_child`.
  - Formation helpers are **spawn layouts only** (IDEAS §35).
- **`AnchorIdle`** (`global/enemy_ai/anchor_idle.gd`) is a `RefCounted` helper.
  - It holds `anchor`, `perceive_radius` < `lose_radius` (hysteresis, both measured actor → target), `notice_time` and
    `hold_combat`, and has `force_notice()`. `update()` returns IDLE / NOTICING / COMBAT / RETURNING.
  - It decides *when* to hand over; the brain decides the idle *motion*. The handover never calls `halt()` or `boost()`.
  - **Assault skips idle** (a provider exists, so the enemy starts in combat).
  - Squads engage and return together: `hold_combat` while `squad.is_engaged()`; `force_notice()` when a mate engages.
- **`EngagementBudget`** (`global/enemy_ai/engagement_budget.gd`) is a `RefCounted` helper, active only when
  `EnemyWorld.arena(tree)` exists. When it expires, the brain goes to DISENGAGE: `EnemyMover.release_constraint()`
  (new), `mover.max_speed = exit_speed`, `seek` the nearest point outside `projectile_world_rect()`, free when outside.
  A drone that leaves is an *escape* for `ScoreTracker` (legacy parity). Mover field writes are not motion writes; the
  single-writer allowlist stays empty.
- **`MovementConstraint.inner_rect() -> Rect2`** is new. The identity returns an empty rect (unbounded); the corridor
  returns its visible rect. Brains clamp orbit centres with it rather than naming `ArenaCamera`.
- **`StateLight`** (`global/components/state_light.gd`) is a presentation child with the states OFF / ARMED (red) /
  CHARGING (yellow) / COMMIT (white) and `blink_once()`. Its texture is a code-built radial `GradientTexture2D` with a
  transparent edge (never scene-authored), coloured by `modulate` (alpha ≤ 0.85).
  - It is the one gameplay light per state (IDEAS §21.1). Later roster phases reuse it; they do not recolour hulls.
  - **COMMIT (white) is exclusive to a real attack.** A feint may only show CHARGING.
- **`Steering` additions:** `spiral`, `corkscrew`, `formation_slot`, `separation`, `alignment`, `cohesion`,
  `clamped_lead_time` and `turn_toward`. Flocking terms are only ever an `add_nudge()` capped at a fraction of
  `max_speed`; the primary request stays single (Phase 1 rule).
- **New enemies:** `assault/scenes/enemies/swarm_drone/` (`SwarmDrone`, `SwarmDroneBrain`, `SwarmDroneConfig`) and
  `assault/scenes/enemies/razor_drone/` (a `git mv` of `drone_interceptor/`: `RazorDrone`, `RazorDroneBrain`,
  `RazorDroneConfig`). Both export `patrol_anchor` (defaults to the spawn position).
  - Enemies that fly in both modes still live under `assault/scenes/enemies/` until Ph15 moves `BaseEnemy`, because the
    invariant gates sweep that directory.
  - `WaveBuilder.DRONE` → the Swarm Drone scene. `DRONE_INTERCEPTOR`/`drone_interceptor()` → `RAZOR_DRONE`/`razor_drone()`.
- **Open Space hub:** `SectorHub._spawn_patrol()` with `patrol_seed`, `squad_size` 4, `patrol_ring_radius` 1000,
  `swarm_anchor_bearing_deg` 90 and `razor_anchor_bearing_deg` 270 — fixed bearings in the planet-free arcs. A test
  checks every planet, pickup and the player spawn stays out of each group's `perceive_radius`; **Ph13's
  EncounterDirector must keep an equivalent clearance check** when it replaces this spawn.
- **Retired:** `kamikaze_drone/` (t14) and `open_space/.../patrol_drone.*` + `test_patrol_drone.gd` (t16). The Bonus
  Drone is unchanged.
- **Test seams:** Razor `force_next_choice(&"real" | &"fake" | &"reverse")`. `SectorHub.patrol_seed`.

### Conventions
- **Rammers are armed only in their committed state**, and the `StateLight` shows it (red). Touching an unarmed rammer
  deals 0.
- **"Missed attack"** means the boost ended with no `contact_made`, never a distance threshold.
- **A curve's per-tick heading change is bounded by the brain's turn rate**, and every config that curves pins
  `turn_rate × speed ≤ acceleration` so the mover can follow.
- **Assault AI lifetimes are derived and checked against the level:** Swarm `engage_seconds` 5.5 s = legacy on-screen
  time (3.5 s) + one attack cycle (1.65 s), rounded up. A test keeps
  `last_wave_max_delay + engage_seconds + exit_distance / exit_speed + exit_speed / (2·acceleration) + 0.5 s` under
  `enemies_cleared_timeout` for every ENEMIES_CLEARED section (9.58 s < 10 s today). Razor 9 s, only in DURATION
  sections — the same test fails if a Razor is added to an ENEMIES_CLEARED section.
- **Level density is a gated number:** level 1's peak concurrent drones are pinned (legacy 14 / 6 / 5 per section).
  After t15, the attack-capable peak (LEAD + FLANKs) may be at most 2.0× legacy and the all-drones peak at most 2.5×.
  The pre-approved levers, in order: `rear_engage_seconds` toward 3.5 s, Swarm `engage_seconds` down to 4.5 s, split a
  6–7-drone loose wave into two squads.
- The contact-damage and contact-geometry gates get **roster completeness guards** (t1). A new enemy directory under
  `assault/scenes/enemies/` fails them until it is added.

### Deliberately deferred
| Item | Deferred to | Reason |
|---|---|---|
| Armour collision profile | Ph4 | Ram Corvette |
| Squad messages (`TARGET_MARKED`, …) | Ph14 | Only role assignment and shared engagement are in scope |
| Idle profiles for other families | Ph14 | Must use `AnchorIdle` |
| Leash / search / hub respawn / Salvage Drone event | Ph13 | EncounterDirector |
| Other level-1 enemies off rails; retiring `SineMovement` etc. | Ph15 | |
| `BulletPool` container injection | Ph5 | Not needed yet (see above) |
| Enemy friendly fire (blasts, beams) | undecided (Ph8 at the earliest) | No design decision yet |
| Enemy audio telegraphs | Ph17 | No enemy SFX pipeline exists |
| Level-1 swarm balance by feel | owner playtest | The gate cannot judge fun; the concurrency ratios above are the gated floor |

### Built in t3-contact-profile (2026-09-27): details later phases depend on

- `ContactProfile` (`global/components/contact_profile.gd`) and `ContactBlast` (`global/components/contact_blast.gd`)
  follow plan §2.3's API exactly. `BaseEnemy.contact_profile` is always non-null after `_ready()`.
- **Deviation:** the blast is parented by a deferred call **on the blast**, `ContactBlast._attach(container)`, not
  `container.add_child.call_deferred(blast)`. If the container is freed first, the engine drops a deferred call on the
  container and the orphaned blast leaks. `_attach` has an untyped parameter and `queue_free()`s the blast when the
  container is gone. Timing is unchanged: both run in the same message flush. (Task review, round 2.)
- COLLISION never writes the hitbox (not even `monitorable = true`), so `SpaceStation`'s death-time
  `collision_layer = 0` and every legacy scene's authored flags stay as they are. The Kamikaze and the Interceptor
  still connect `contact_hit_box.area_entered` themselves; t8b and t9 move them onto `contact_made`.

### Built in t4-squad-controller (2026-09-27): details later phases (t5, t8c, Ph3) depend on

- `SquadController` (`global/enemy_ai/squad_controller.gd`) follows plan §2.4's API, with three
  resolutions the round-2 review left to this task (N13, N14, N3's "only strong reference" claim):
- **Assignment is a full recompute, not an incremental fill.** `join()`, `leave()` and
  `release_lead()` all call one `_reassign()` that re-sorts every current member by distance to
  `target_position_hint` (ties by join order) and reassigns LEAD/FLANK_LEFT/FLANK_RIGHT/REAR from
  scratch every time. This is what makes "LEAD goes to the closest member" a live invariant rather
  than a one-time election (round-1 N14 asked for the opposite — join() only fills a vacancy — but
  that cannot produce "the lead is closest to the hint" as a steady-state property, which t4's own
  acceptance criteria required). The plan's reassignment bullets ("existing flanks keep their role
  unless one becomes the new lead", "the closest REAR fills the vacated flank") are a **consequence**
  of this design when a lead is removed, not a separate code path — verified in
  `test_freeing_the_lead_reassigns_in_the_same_call`. `release_lead(member)` is the one exception:
  it pins the releasing member to REAR for that call (`_reassign(force_rear)`), because a plain
  recompute would just re-elect the same still-closest member and never rotate the token.
  **Consequence for t5/t8c:** a squad member's role can change on every teammate's join, not only
  on death — a brain reading `squad.role_of(self)` every tick (as §2.7.2 already assumes) sees this
  correctly; nothing should cache a role across ticks.
- **`attack_window_open` self-clears (round-1 N13).** Only the current LEAD is ever supposed to set
  it true (§2.7.2), so `leave()` and `release_lead()` clear it whenever the departing/releasing
  member held LEAD. A brain still sets it directly (`squad.attack_window_open = true`) on entering
  BURST — this is a safety net against it sticking open after a lead free, not a new API.
- **`claim_side()`/`release_side()` take and return `int`, not `Side`.** Passing
  `SquadController.Side.LEFT` from another script into a parameter or return typed `Side` fails to
  compile under Godot 4.6's static checker — the same cross-script nested-enum mismatch that
  already made `role_changed` declare `role: int` rather than `Role`. Any caller (t8c, t10) passes
  `SquadController.Side.LEFT`-style values as plain ints; comparisons and dictionary keys still work
  because enum members are ints underneath.
- **"Members hold the only strong reference" is the member's own `squad` property, not the
  `tree_exiting` connection `join()` makes.** Probed directly: connecting
  `member.tree_exiting.connect(leave.bind(member))` does **not** keep a `RefCounted` target alive in
  this Godot version once every other reference is dropped. The board only survives via whatever the
  caller stores it in (`entity.set("squad", board)`, §2.4.1) — `WaveManager`'s `_squads` map must
  keep only `WeakRef`s as planned, and t5 must give the spawned entity a `squad` property before
  `add_child()`, or the board is never kept alive by anything and dies on the next reassign's prune.

### Built in t8b-swarm-solo (2026-09-27): details t8c, t8d, t14 and t15 depend on

Task plan `docs/plans/cmuj4y8rh0070p52xk6vzfvbe/` (two review rounds, approved round 2).

- **Config deviations from the §2.7 table.** `braking` **900** (not 500): epic review round 2 B5 was
  never folded into the plan — at 500 the overshoot sheds 480 → 220 px/s for 0.52 s of its 0.8 s and
  turns only ~44°; at 900 it turns ~76°. The config test pins both `overshoot_turn_rate × max_speed ≤
  acceleration` and `overshoot_turn_rate × (overshoot_seconds − (burst_speed − max_speed) / braking) ≥
  60°`. The epic's "turns up to about 110°" was wrong. `max_turn_rate` **10** rad/s (not 5) and the
  mover's `turn_lerp` **20**, so the 0.4 s wind-up can swing the nose through 180° onto the burst line.
  `corkscrew_amplitude` **120 px/s at 0.6 Hz** (not 60 at 1.5): `Steering.corkscrew`'s amplitude is a
  *velocity*, lateral swing ≈ amplitude / (2π·f), so 60 @ 1.5 Hz swung ~6 px on a 32 px hull.
- **`SwarmDroneBrain.phase_changed(new_phase: int)`** is emitted on every transition; `enter_phase(p)`
  is the one transition path and the test seam. Phases: APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT,
  REJOIN, DISENGAGE. t8b constants t8c repoints at config: `APPROACH_EXIT_RADIUS` 360,
  `CLOSE_IN_RADIUS` 200. CLOSE_IN spirals with `radius_rate` 0 (only the ring shrinks, 120 px/s) and a
  130 px/s tangential anchor so the anchor never outruns `max_speed`.
- **Brain tunables are copied by `SwarmDrone._ready()`, which runs after the brain's own `_ready()`**,
  so the `EngagementBudget` and `passes_left` are built on the brain's first tick, never in `_ready()`.
  Any brain whose root copies config onto it must do the same.
- **No DISENGAGE deferral through a burst (instead of epic review N19).** WINDUP is entered only while
  `budget.remaining() ≥ windup + burst + (burst_speed − max_speed)/braking + 0.15 s` (1.29 s), so the
  budget can only expire outside a burst, at ≤ `max_speed`, and DISENGAGE starts exactly at
  `engage_seconds`. The §2.6 formula needs no burst term. New: `EngagementBudget.remaining()` (INF when
  inactive). Honest residual (plan review round 2): the formula assumes the exit starts from rest; a
  drone moving at 220 px/s away from its exit edge loses ~0.49 s more — worst case ≈ 9.57 s, still
  under 10 s; t15's integration case is the arbiter.
- **Lock timing:** the aim and lead are re-evaluated every WINDUP tick (the nose visibly tracks) and
  locked on the last one, so `lead_time` is measured from the burst's start.
- **Squad calls:** `update_target` each tick; `claim_side` on WINDUP entry (the sector the drone is in,
  by the same cross-product sign as `SquadController`'s flanks), aim offset one hull width (32 px)
  toward it; `release_side` on OVERSHOOT; `release_lead` at REJOIN **only with ≥ 2 members** —
  `release_lead` on a sole member pins it to REAR with nobody to take LEAD, and every loose level spawn
  is a squad of one (t5). t8c: either keep this rule or teach `SquadController.release_lead` that a sole
  member keeps LEAD. DISENGAGE and rail suspension call `squad.leave(self)`. `SwarmDrone.squad` is the
  duck-typed slot `WaveManager` writes; `SwarmDrone._ready()` calls `update_target` then `join`.
- **DISENGAGE picks the nearest edge of `projectile_world_rect()` once, on entry** (not every tick),
  seeks 64 px past it, frees once strictly outside the rect (re-read each tick).
- **Epic §4 "a burst toward a stationary player uses facing"** was read as: the aim degenerates to the
  player's position and the drone's own facing at burst start lies along the burst direction (the
  wind-up telegraph points where it goes) — not the player's `TargetInfo.facing`.
- **Placeholder art:** `drones.png` cell 0 cropped `Rect2(2,2,38,38)` (the sheet is 3×2 cells of 42×42
  with grid marks on the cell borders); its nose points **down**, so `sprite_forward_angle` stays
  `BaseEnemy`'s default `PI/2`. t12 replaces it (and sets its own forward angle).
- Collision circle r 13 shared by body, `HurtBox` and `ContactHitBox` (one sub-resource, scale 1).
  `swarm_drone` is in the contact-damage, contact-geometry and hurtbox-geometry rosters; the deadline
  test reads `swarm_drone_config.tres`.

### Built in t8c-swarm-squad (2026-09-27): details t8d, t15, t16 and Ph3/Ph14 depend on

Task plan `docs/plans/cmuj4y8rj0074p52xqmin24gu/` (two review rounds, approved round 2 with amendments A1–A2).

- **`SwarmDroneBrain.Phase.FORM` is appended** (value 7), so t8b's phase values are unchanged. APPROACH hands over at
  `rear_orbit_radius + 100` to CLOSE_IN (LEAD) or FORM (others); CLOSE_IN, FORM and REJOIN fall back to APPROACH
  beyond `rear_orbit_radius + 200`. CLOSE_IN's ring is `flank_distance`. The t8b constants `APPROACH_EXIT_RADIUS`,
  `APPROACH_REENTER_RADIUS` and `CLOSE_IN_RADIUS` are gone.
- **`rear_orbit_speed` 0.55 rad/s, not the epic table's 1.4** (D1): 1.4 × 260 px = 364 px/s is beyond `max_speed`
  220, so a REAR could never hold the ring. A config test pins `rear_orbit_speed × rear_orbit_radius ≤ 0.7 ×
  max_speed`.
- **`phase_offset` is bounded to ±0.35 rad** (D2), drawn from `rng` after t8b's draws. An offset anywhere in
  `[0, TAU)` would undo the ring's index spacing. t8d's idle ring uses the same field.
- **The REAR ring's angle is shared state on the board** (D3): `SquadController.rear_ring_angle` (`NAN` until a REAR
  in FORM finds it unset and starts it at its own bearing), advanced only by `rear_index == 0`, never reset. New
  `SquadController.rear_count()`. A REAR orbits `inner_rect()`-clamped centres in Assault.
- **The attack window** (D4 and review B4/A1):
  - The LEAD opens it on BURST, but only if it wound up as LEAD **and** still leads.
  - `SquadController._reassign()` closes it **whenever the LEAD member changes**, whatever the cause. This replaces
    t4's two special-case clears.
  - A sole member closes its own window at REJOIN.
  - A FLANK answers each window **once** (`_answered_window`, reset whenever the window reads closed). So the lead's
    second-pass burst does not trigger a second flank attack.
  - Consequence, expected: a kill that moves the lead through the distance recompute closes the window, and the flanks
    wait for the new lead's burst.
- **Role changes mid-pass:** `_pass_role` is taken on WINDUP entry. A different role at the end of OVERSHOOT skips any
  remaining pass (→ REJOIN). REJOIN hands the lead on only after a pass made as LEAD by a drone that still leads.
- **Nudge:** flocking (separation × 6, (mean mate velocity − own) × 0.1, cohesion × 0.05) plus `Steering.evade`
  inside `evade_radius`, capped at `flock_nudge_cap × max_speed`, offered **only in APPROACH, CLOSE_IN and FORM**. It
  is never offered in OVERSHOOT, because t8b's per-tick curve bound assumes the one request. A mate's velocity is
  read only from a `CharacterBody2D`.
- **Per-role budget:** in Assault, a REAR in APPROACH/FORM expires at `rear_engage_seconds` (5.5, pinned
  `≤ engage_seconds`). No new `EngagementBudget` API: elapsed is `seconds − remaining()`.

### Built in t8d-swarm-idle (2026-09-28): details t11-razor-idle and t16-hub-patrol depend on

Task `cmuj4y8rm0078p52x5qa7v6fo`. `AnchorIdle` and `SquadController.set_engaged/is_engaged` already existed
(t7-anchor-idle, t4-squad-controller); this task is the first thing to wire either into a real brain.

- **`patrol_anchor` sentinel: `Vector2.INF` means "unset".** `SwarmDroneBrain._start()` defaults it to
  `actor.global_position` the first tick it is still `Vector2.INF` (`Vector2.is_finite()` checks it). A real squad
  spawner (t16) sets the SAME `patrol_anchor` value on every member **before** `add_child`, so they share one ring;
  a lone drone left unset patrols around wherever it spawned. **t11-razor-idle's own `patrol_anchor` ("defaults to
  the spawn position") should reuse this exact sentinel**, not invent a second convention.
- **`SwarmDroneBrain.start_engaged` is a test-only seam**, not a gameplay flag: every t8b/t8c test built a drone
  assuming combat-from-spawn, which stopped being the Open Space default the moment idle existed. Setting it true on
  the brain (before the first `tick()`) skips `AnchorIdle` construction and starts in APPROACH exactly as before —
  every existing `test_swarm_drone.gd` helper (`_spawn`, `_squad_drone`, `_squad_of`, `_real_drone`, and the FORM
  contact-safety loop) sets it so none of those cases changed behaviour. **t11-razor-idle will hit the identical
  problem** (`test_razor_drone.gd` / `test_drone_interceptor.gd`'s existing cases assume immediate combat) and should
  add the same seam rather than rewrite those tests' geometry.
- **Engagement precedence (review round 2, N17):** `squad.set_engaged(member, on)` is computed fresh every tick as
  `on = (anchor_idle_state in {NOTICING, COMBAT}) and distance_to_player < lose_radius` — never from `hold_combat`
  or the Phase enum alone. Without the distance term, a member held in COMBAT by its squad mates (via `hold_combat`)
  would itself always read as "engaged", and the squad could never lose the player at all.
- **The idle ring's shared angle is per-member, not board state** (unlike the REAR ring's `rear_ring_angle`): each
  member computes `phase_offset + join_index × TAU / squad_size + idle_speed × t` independently, where `t` is its own
  `_phase_time` since last entering IDLE. New `SquadController.member_index()` / `member_count()` — whole-squad join
  order, unlike `rear_index()` / `rear_count()`, which only count REARs. **t16-hub-patrol and any later squad-wide
  ring should use these**, not re-derive join order by hand.
- **NOTICING owns no timer of its own** — `AnchorIdle` already tracks `notice_time` internally; the brain's
  NOTICING phase only blinks the light once (entry) and calls `face_toward` every tick, and hands over to APPROACH
  the moment `AnchorIdle.update()` reports COMBAT. That handover can cascade into CLOSE_IN/WINDUP **within the same
  physics tick** if the player is already close (the existing bounded `for _i in 4` chain in `tick()`), same as any
  other same-tick phase chain in this brain.
- **RETURNING never interrupts a live BURST** (same guard the budget-expiry check already used): `AnchorIdle`'s own
  state can flip to RETURNING mid-burst, but the brain's `Phase` only follows on the next tick once the burst has
  ended, so a contact-armed pass always finishes.

### Built in t10-razor-combat (2026-09-28): details t11, t13, t15, t16 and later phases depend on

Task plan `docs/plans/cmuj4y8rr007gp52xxs8dec5s/` (two review rounds; approved in round 2 with amendments A1–A5).

- **`RazorDroneBrain.Phase`** is `ENTER, ORBIT, DASH, REVERSE, FEINT_WINDUP, FEINT_LUNGE, FEINT_BRAKE, WINDUP,
  OVERSHOOT, RETURN, DISENGAGE`.
  - The first three keep their Phase 1 values. **t11 appends IDLE, NOTICING and RETURNING-to-anchor.** The combat
    `RETURN` is the post-overshoot return to the orbit ring, so t11 needs a different name for the anchor return.
  - `phase_changed(new_phase: int)`, `enter_phase()` (the one transition path and test seam), and
    `force_next_choice(&"real" | &"fake" | &"reverse")`.
  - Public read-only state: `orbit_dir`, `angular_speed`, `orbit_centre`, `dash_direction`, `dash_hit`, `pulses_fired`,
    `lunge_side`, `budget`. `static lane_angle_deg(rel)`.
  - Like the Swarm, it builds its budget on the first tick, because the root copies the config after the brain's
    `_ready()`. **t11 needs the Swarm's `start_engaged` test seam for exactly this reason:** every
    `test_razor_drone.gd` case assumes combat from spawn.
- **Deviation: the feint lunge aims `feint_clearance_px` (70) beside the player, not 25° off it.**
  - The drone actually orbited at 82–110 px, not 130, because `orbit_correct_speed` 160 < `orbit_speed ×
    orbit_radius` 234. A 25° lunge from there passed 37–46 px from the player, *through* its 44 px hull + hurtbox.
  - **`orbit_correct_speed` is now 260** (orbit ≈ 119 px on every seed), and a config test pins ≥ `orbit_speed ×
    orbit_radius`.
  - Measured result: closest approach 61.7 px, sweep 128.3°.
- **"The fake ends > 120° round from where it started"** is measured from the bearing at **FEINT_LUNGE entry** (the
  hold point it lunges from). This is also what the epic's N5 ≈ 130° assumed. From FEINT_WINDUP entry the hold's
  drift makes it about 111°.
- **Deviation: a reversal bars the next reversal until the next attack begins**, not "once per window". Read
  literally, "once per window" allows endless back-and-forth reversals.
- **The Assault side lane is checked at the point the real dash will start from**, not at the drone's current position:
  - for a real attack, the WINDUP hold point (the stopping point `pos + v̂·|v|²/(2·braking)`);
  - for a feint, the predicted far-side stop, with the lunge side chosen so it lands in a lane;
  - the check band is narrowed by 3° at each end, and an attack waits at most 2 s for a lane.
  - The post-feint dash therefore comes from a lane too, with no orbit leg.
- **The orbit re-anchors on ENTER → ORBIT** (and on RETURN and after FEINT_BRAKE) to the drone's own bearing. It is
  never started on the far side of the player.
- **FEINT_LUNGE and FEINT_BRAKE show the light OFF**, not CHARGING. The fake reads yellow → dark → then the real
  yellow → white → red.
- **Pulse:** a scene-authored `BulletPool` (4) and `AttackController` (`driven_by_brain`, `enabled = false`), fired
  with `fire_now()` once at OVERSHOOT entry after a miss.
  - The `AimedAttackPattern` is **built per instance** in `razor_drone.gd`, never as a scene sub-resource, because
    those are shared between instances.
  - A budget expiring during a dash goes straight to DISENGAGE after the boost, so that dash fires no pulse.
- **Budget expiry is deferred while the mover is boosting.** `test_engagement_deadline.gd` now judges each kind by its
  own config and gives the Razor a conservative formula that includes the deferral. A boundary case asserts that a
  Razor placed in cloud_descent would miss the 10 s timeout (about 15.4 s). **Razors must stay out of
  ENEMIES_CLEARED sections** unless that formula is revisited.
- **Removed:** `dash_max_distance`, `_begin_dash()`, `_check_dash_end()` and the contact self-kill.
  `EnemyWorld.cull_rect()` / `ArenaCamera.enemy_cull_rect()` **now have no production consumer**, but they are kept,
  and a later cleanup (Ph15/Ph17) may retire them.
- **Scene:** `ContactProfile` (RAMMING), `StateLight` at (0, −10) (t13 may move it for the new sprite), `BulletPool`
  and `AttackController`. `test_base_enemy.gd`'s `_AUTHORED_CONTACT_MODES` gains `razor_drone → RAMMING`.

### Built in t11-razor-idle (2026-09-28): details t16-hub-patrol depends on

Plan §2.8.4. Follows the t8d-swarm-idle precedent above (`AnchorIdle`, the `patrol_anchor` sentinel, the
`start_engaged` test seam), adapted for a single drone with no `SquadController`.

- **`RazorDroneBrain.Phase` gains `IDLE_ORBIT, IDLE_BRAKE, IDLE_REVERSE, IDLE_BOOST, NOTICING, RETURNING`**,
  appended after `DISENGAGE` so every existing pinned value is unchanged. `RETURNING` is deliberately not named
  `RETURN` — that name is already the post-overshoot return to the combat orbit ring, and t11's own `RETURNING`
  must never collide with or interrupt it.
- **`home_radius` is `idle_radius` itself** (160 by default), not `idle_radius + idle_radius_jitter` as an earlier
  draft considered — matching what `SwarmDroneBrain` actually passes (`idle_radius`, not the ~170 the t8d review
  comment estimated). A `RETURNING` drone counts as "home" once within the nominal ring radius of the anchor, not
  the jittered maximum.
- **The idle ring owns its own angle/radius/speed fields** (`_idle_angle`, `_idle_ring_radius`, `_idle_speed_mag`),
  separate from combat's `_orbit_angle` / `orbit_centre` / `angular_speed`. This is load-bearing: `tick()` sets
  `orbit_centre = _centre_of(target.position)` on **every** tick the player exists, regardless of phase, and the
  player exists (just far away) in every idle test. Reusing the combat fields for idle would have let that
  assignment clobber the idle ring's centre every tick; `tick()` now skips it while in an idle-related phase
  (`_in_anchor_idle_phase()`: the four idle legs plus NOTICING and RETURNING) and resumes updating it the moment
  the brain hands over to ENTER.
- **Each idle leg is exactly one of `IDLE_BRAKE` / `IDLE_REVERSE` / `IDLE_BOOST`, equally likely**, drawn from `rng`
  when the current `IDLE_ORBIT` leg's 2–4 s timer runs out; `force_next_idle_leg(&"brake" | &"reverse" | &"boost")`
  is the test seam, mirroring `force_next_choice`. All three hand back to a **fresh** `IDLE_ORBIT` leg (which
  re-anchors and redraws radius/speed/duration) rather than resuming the old one.
- **`IDLE_REVERSE` reuses `reverse_seconds`** (the combat reversal's ramp time) rather than a new config field —
  the two reversals never run concurrently, and the plan's own config-field list for t11 names only the `idle_*`
  triplet, `perceive_radius`, `lose_radius` and `notice_time`.
- **`IDLE_BOOST`'s speed is `1.8 × current leg's tangential speed`** (`idle_speed_mag × idle_ring_radius`), along
  the drone's current velocity direction (its facing, if nearly stopped) — not a fixed exported speed, so a boost
  during a wide, fast leg is a bigger burst than one during a tight, slow leg.
- **`NOTICING → ENTER` needed no new code path**: `enter_phase()`'s match already runs nothing for `ENTER`, so the
  handover keeps the drone's current velocity for free — the same trick t8d used for the Swarm's
  `NOTICING → APPROACH`.
- **`RETURNING` never interrupts a live `DASH`** (the single guarded phase, matching t8d's `BURST` guard for the
  Swarm) — a contact-armed pass always finishes. It is not guarded against interrupting `WINDUP` or the feint
  phases, same judgement call as t8d.
- **Every pre-existing `test_razor_drone.gd` / `test_enemy_dual_mode.gd` case sets `start_engaged = true`** on the
  brain (three spawn helpers: `test_razor_drone.gd`'s `_spawn()`, its two manual `SCENE.instantiate()` cases, and
  `test_enemy_dual_mode.gd`'s `_spawn_razor_drone()`), so none of them changed behaviour.

### Built in t15-level1-ai (2026-09-28): details Ph15 and the phase-2 dossier depend on

Task plan `docs/plans/cmuj4y8s30080p52xxk0ioy1n/` (two review rounds, approved round 2).

- **Every `b.drone()` line in `level_1_director.gd` has no `.move()`** (119 lines), and the two cloud_descent side
  drones lost their `.free_after(5.0)` (read only by `EnemyPathMover`). `.at()`, `.formation()` and `.delay()` are
  unchanged; the t1 pin still matches row for row with `movement: false`, and now also asserts `exit_mode ==
  FREE_ON_SCREEN_EXIT` for every drone and razor entry.
- **Squad ids are `&"w<n>"`, `n` = the wave's 0-based index in its section's `raw_waves`.** Only uniqueness within a
  wave matters (the `WaveManager` key already contains the wave index). 97 loose lines are tagged; a lone loose
  drone stays a squad of one. The station's BOTTOM squad is still on rails.
- **C3: no lever pulled.** Lifetimes from the shipped configs and the live world rect: Swarm attacker/REAR 5.5 s +
  2.78 s worst exit, Razor 9.0 s + its own worst exit (dash deferral included). Peaks, attack-capable (first three
  per squad, plus every Razor) / all: deep_space 17 / 23 (1.21× / 1.64× of 14), planet_approach 7 / 9 (1.17× /
  1.50× of 6), cloud_descent 7 / 10 (1.40× / 2.00× of 5). `test_level1_drone_spawns.gd` asserts ≤ 2.0× / ≤ 2.5×
  per section; the rotating `min(alive, 3)`-per-squad count is printed (same values today), not asserted.
  `rear_engage_seconds` stays 5.5 and `engage_seconds` 5.5.
- **Measured exit:** cloud_descent's last wave, run for real (`test_level1_drone_exit.gd`, stationary hurtbox-less
  player stub), empties in 8.0–8.4 s of game time against the 10 s `enemies_cleared_timeout`, every drone leaving in
  DISENGAGE with no `EnemyPathMover`. The margin is about 1.6 s; a slower exit or a longer budget will trip it.
- **`tests/helpers/level1_drone_concurrency.gd`** gained `worst_exit_seconds()`, `squad_intervals()`,
  `peak_intervals()` and `peak_min_alive_three()` — reusable when Ph15 takes the other level-1 enemies off rails.

### Built in t16-hub-patrol (2026-09-28): `patrol_ring_radius` corrected to 1300, not the plan's 1000

Task `cmuj4y8s70084p52x8g2hl0tm`. `SectorHub._spawn_patrol()` matches §2.11 exactly (`patrol_seed`, `squad_size` 4,
`swarm_anchor_bearing_deg` 90, `razor_anchor_bearing_deg` 270, one shared `SquadController` + `patrol_anchor` for the
Swarm squad, its own `patrol_anchor` for the Razor) with one numeric correction:

- **`patrol_ring_radius` is 1300, not the plan's 1000.** The round-2 review's B6 fix computed the Razor's nearest
  interactable as `ModuleUnlockerEmpBlast` (−280, −315) at 740 px, giving 740 − 200 = 540 > 450 and landing in the
  approved plan's own table and AC ("Razor 540 > 450 on today's scene"). A full sweep over every `MissionTrigger` and
  `PickupBase` child of `sector_hub.tscn` (not just the one pickup row the plan's manual check looked at) finds a
  closer one at 1000 px: `WeaponUnlockerMiningLaser` (20, −515), 485 px from (0, −1000) — clearance 485 − 200 = 285,
  **below** 450. The plan's own arithmetic missed the y = −515 weapon-unlocker row. Raising the shared
  `patrol_ring_radius` to 1300 (one of B6's two suggested fixes) restores clearance for both groups against every
  interactable, computed and pinned in `tests/integration/test_sector_hub_patrol.gd`: Swarm 543 > 380 (nearest now
  `LoreLogFortunaManifest`, 1093 px), Razor 135 > 450 margin (nearest still `WeaponUnlockerMiningLaser`, now 785 px).
- **`test_sector_hub_patrol.gd`'s clearance cases sweep every direct `MissionTrigger`/`PickupBase` child and the
  player spawn**, rather than checking named points by hand — the same generic-sweep fix applied to the geometry
  check itself, so a pickup added later that lands too close fails the gate instead of silently repeating this bug.
- **The spawn-behaviour cases (composition, shared anchors, seed reproducibility, frame-0 perception, the pulse's
  container) run against a minimal harness** — the real `sector_hub.gd` script plus a bare `EnemyContainer` child,
  under `enemy_ai_harness.gd`'s `open_space()` root — rather than the full `sector_hub.tscn` (player ship, HUD, three
  mission triggers). The full scene loads cleanly inside a real GUT test (autoloads registered), but nothing here
  needs the extra weight; the clearance cases already cover the real scene's node positions.
- **`PatrolDrone`/`patrol_drone` is gone from every `.gd`/`.tscn`/`.tres`** — the two source files, its own
  characterization test, and every comment that used to name it (`swarm_drone.gd`, `steering.gd`, `sector_hub.gd`,
  `test_level1_drone_spawns.gd`). `test_sector_hub_patrol.gd`'s own sweep for the name builds its search terms by
  string concatenation rather than as a literal, so the sweep file does not trip on itself.

## Phase 2 - as built (2026-09-28)

All 20 build-sequence tasks (t1, t2, t3, t4, t5, t6, t7, t8a–t8d, t9, t10, t11, t12, t13, t14, t15, t16, t17-docs)
landed on `agent/auto-dev`, plus the plan/research/review preparation tasks and three rounds of plan review
(`4-review.md`: round 1 CHANGES_REQUESTED on B1–B4, round 2 CHANGES_REQUESTED on B5–B6, round 3 APPROVED). This
closes the epic. `docs/epics-done/cmufs7ek60001nm2x6d0bt2et/` has the full dossier (PRD/SOURCES/REPORT); this
section is the short version Phase 3 and later phases should read first, alongside the per-task "Built in tX" notes
above, which this section indexes rather than repeats.

### What was actually built

Everything in the "Names and places" and "Conventions" tables above landed **as specified**, checked against the
final source on `agent/auto-dev`: `global/components/contact_profile.gd` + `contact_blast.gd`,
`global/enemy_ai/squad_controller.gd` + `anchor_idle.gd` + `engagement_budget.gd`, `global/components/state_light.gd`,
the `Steering` additions (`spiral`, `corkscrew`, `formation_slot`, `separation`, `alignment`, `cohesion`,
`clamped_lead_time`, `turn_toward`), `MovementConstraint.inner_rect()` / `AssaultCorridorConstraint.inner_rect()`,
`EnemyMover.release_constraint()`, `WaveBuilder.SpawnConfig.squad()` / `SpawnEntryResource.squad_id`, and the two
enemies: `assault/scenes/enemies/swarm_drone/` (new) and `assault/scenes/enemies/razor_drone/` (`git mv` of
`drone_interceptor/`, classes and constants renamed). Both fly in both modes, both have dedicated top-down art
(swarm 32×32, razor 48×48) and a `StateLight`, and both are wired into every invariant gate's roster. The Open
Space hub's ambient spawn is a Swarm squad + a Razor Drone (`SectorHub._spawn_patrol()`); level 1's drone and
Razor spawns run off rails, as squads, under the corridor constraint, with the same triggers/offsets/delays as
before (`test_level1_drone_spawns.gd`'s t1 pin, updated in place rather than replaced). `KamikazeDrone`,
`DroneInterceptor` and `PatrolDrone` are gone from the codebase; the Bonus Drone is untouched.

### Deviations from `3-plan.md`

Every deviation below is already recorded in detail in its task's "Built in tX" note above; this list is the
index, in build order, so a later phase can scan it without re-reading all nine notes.

- **t3 (`ContactProfile`/`ContactBlast`):** the blast parents itself via a deferred call **on the blast**
  (`ContactBlast._attach(container)`), not `container.add_child.call_deferred(blast)` as §2.3 wrote it — so an
  already-freed container drops the deferred call safely instead of erroring. See "Built in t3-contact-profile".
- **t4 (`SquadController`):** round-1 N14 asked for `join()` to only fill a vacancy; the round-2 review of
  `3-plan.md` left the actual resolution to this task, which built a **full recompute on every join/leave/release**
  instead, because that is
  the only design where "LEAD is whoever is closest to the hint" is a standing property rather than a one-time
  election, which the epic's own acceptance criteria needed. `attack_window_open` self-clears whenever `_reassign()`
  changes who holds LEAD, not only on a clean burst end. `claim_side()`/`release_side()`/`role_changed` pass
  `Side`/`Role` as plain `int` (a Godot 4.6 static-checker constraint on cross-script nested enums, same shape as an
  existing `role_changed` decision). See "Built in t4-squad-controller".
- **t8b (Swarm solo cycle) config, three numbers off the plan's own §2.7 table:** `braking` 900 not 500 (the plan's
  own round-2-approved fix for its round-1 B5, never folded into the table); `max_turn_rate` 10 not 5; `corkscrew_
  amplitude` 120 px/s @ 0.6 Hz not 60 @ 1.5 Hz (the plan's number produced a ~6 px swing on a 32 px hull because the
  primitive's amplitude is a velocity, not a displacement). The overshoot turns ~76°, not the plan's "~110°". See
  "Built in t8b-swarm-solo".
- **t8c (Swarm squad) config, two numbers (D1, D2) plus one API addition (D3, D4) off the plan:** `rear_orbit_speed`
  0.55 rad/s not the table's 1.4 (1.4 × 260 px exceeds `max_speed`, so a REAR could never hold the ring);
  `phase_offset` bounded to ±0.35 rad, not the plan's unstated full range; the REAR ring's shared angle is new board
  state (`SquadController.rear_ring_angle`); the attack window's closing rule generalizes t4's two special cases into
  one (closes whenever the LEAD changes, for any reason). See "Built in t8c-swarm-squad".
- **t8d (Swarm hub idle):** the `patrol_anchor` sentinel is `Vector2.INF` ("unset"), not stated in the plan; the
  engagement-precedence formula (round-2 review N17) is computed fresh every tick from distance and `AnchorIdle`
  state, never cached from `hold_combat` alone (the plan's §2.7.3 wording under-specified this and would have let a
  squad-held member always read as self-engaged). See "Built in t8d-swarm-idle".
- **t10 (Razor combat), the largest single set of deviations, mostly geometry corrections found live rather than by
  arithmetic on paper:** the feint lunge aims `feint_clearance_px` (70 px) beside the player, not the plan's 25°
  offset — the drone's real orbit radius (measured ~82–110 px, not the plan's assumed 130) made a 25° lunge pass
  *through* the player's hull; `orbit_correct_speed` raised to 260 (from a lower value) so the orbit actually holds
  ≈119 px; a reversal now bars the *next* reversal until the next attack begins, not "once per window" (the literal
  plan wording allowed endless back-and-forth); the Assault side-lane check reads the drone's position **at the
  point the real dash will start from** (the WINDUP hold point, or the feint's predicted far-side stop), not its
  current position; the orbit re-anchors to the drone's own bearing on every re-entry, never to the far side of the
  player; a feint shows the light **OFF**, not CHARGING, during its lunge and brake legs (CHARGING is reserved for
  the real WINDUP); a budget expiring mid-dash goes straight to DISENGAGE after the boost with no pulse fired; and
  the deadline formula defers a Razor's budget expiry while it is boosting, since a dash cannot be cut off mid-flight
  — pinned in `test_engagement_deadline.gd` with a boundary case showing a Razor in an `ENEMIES_CLEARED` section
  would miss the timeout (~15.4 s), which is why Razors are restricted to `DURATION` sections (`deep_space` only).
  `dash_max_distance`, `_begin_dash()`, `_check_dash_end()` and the dash's contact self-kill are removed outright,
  since the Razor now survives its dash. See "Built in t10-razor-combat".
- **t11 (Razor hub idle):** `home_radius` is `idle_radius` itself (160), not `idle_radius + idle_radius_jitter`
  (~170) as the round-2 review's own estimate assumed — matching what `SwarmDroneBrain` actually passes. See
  "Built in t11-razor-idle".
- **t15 (level 1 off rails), §5 C3 concurrency: no lever pulled.** The plan pre-approved three levers (lower
  `rear_engage_seconds`, lower Swarm `engage_seconds`, split a large loose wave) to use *only if* a section's
  post-migration peak exceeded the ceiling. Measured against the real shipped configs and the live world rect, every
  section stayed inside it without touching any of them: attack-capable / all-drones peaks were deep_space 17/23
  (1.21×/1.64× of the legacy 14), planet_approach 7/9 (1.17×/1.50× of 6), cloud_descent 7/10 (1.40×/2.00× of 5) —
  against the pre-approved ceiling of ≤ 2.0× / ≤ 2.5×. `rear_engage_seconds` stays 5.5 and Swarm `engage_seconds`
  stays 5.5, both at their t8b/t8c defaults. See "Built in t15-level1-ai".
- **t16 (hub patrol):** `patrol_ring_radius` is 1300, not the plan's 1000. The plan's own round-2 B6 fix had already
  corrected the round-1 ring radius once, using a manual check of one pickup row; t16's full sweep of every
  `MissionTrigger`/`PickupBase` child of the real `sector_hub.tscn` found a second, closer interactable the manual
  check missed (`WeaponUnlockerMiningLaser`, 485 px from the plan's 1000 px anchor — inside the Razor's 450 px
  `perceive_radius`), so the radius went to 1300 to restore clearance for both groups against everything in the
  scene, not just the one row checked by hand. See "Built in t16-hub-patrol".
- **t9 (rename), t12/t13 (art), t14 (Kamikaze swap under rails), t1/t2/t6/t7 (foundations):** no deviation from the
  plan surfaced during these tasks that a later phase needs to know about; each has no "Built in tX" note above for
  that reason.

### Gaps left for later phases

Everything in the "Deliberately deferred" table above still stands. In particular, for the phases that read this
section next:

- **Phase 3 (Fighter, Gatling Interceptor)** is the first roster phase to reuse `SquadController` for a
  non-drone family, and the first to need `Steering.lead_target` / `break_contact` (both still deferred).
- **Phase 4** owns the Armour contact-collision profile (the `ContactProfile.Mode` enum is already shaped for a
  fifth case), real line-of-sight, and the Ram Corvette.
- **Phase 5** owns `BulletPool`'s injectable grandparent container (deferred a second time in this phase — every
  real parent chain still satisfies pool → ship → container, so nothing forced it) and owner-bound projectile
  lifetime (`persist_after_owner_death`).
- **Phase 13 (EncounterDirector)** must replace `SectorHub._spawn_patrol()` with an equivalent per-group clearance
  check — the geometry test this phase shipped (`test_sector_hub_patrol.gd`) is pinned to the hub's own static
  scene layout, not to a director that can place drones dynamically.
- **Phase 14** owns squad messages beyond shared engagement (`TARGET_MARKED` and friends) and idle profiles for
  every family besides these two drones — both must build on the `AnchorIdle` contract this phase shipped, not a
  new one.
- **Phase 15** owns taking every other level-1 enemy off rails, retiring `SineMovement` and friends, and moving
  `BaseEnemy` itself into `global/`.
- **Phase 17** owns the readability audit for the rest of the roster and, if the owner wants it, enemy audio
  telegraphs — this phase shipped none (no enemy SFX pipeline exists anywhere in the project).
- **Known gaps the gate cannot see, left for a human:** whether the Swarm and Razor read as fun and distinct in
  play, whether level 1's new density (drones alive ~8.3 s instead of ~3.5 s) feels right despite passing the C3
  ceiling, whether the `StateLight` cues read at Assault's speed, and whether the hub patrols stay quiet while the
  player dwells at a planet's mission trigger or the pickup bench (`sector_hub.tscn`'s pickups sit closer to the
  Razor's patrol ring than the planets do). `docs/epics-done/cmufs7ek60001nm2x6d0bt2et/REPORT.md` lists these as
  known gaps in full, plus the hand-playtest checklists t15 and t16 ended their runs with.
- No numeric collision-layer bit changed meaning or value in this phase.

## Phase 3 - Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family (2026-09-29)

These are the **planned** decisions:
- plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` (**revision 2**, which answers the owner's
  CHANGES_REQUESTED review; its §9 maps each point);
- research: `1-context.md` and `2-research.md` in the same directory;
- tasks: `tasks.json` (19 tasks, t1–t18, with t8 split into t8a/t8b).

Once this phase's *as built* section exists, check it first.

### Changes to Phase 1 and 2 decisions (plan §2.0)
- **Rails and brain-driven fire (Ph1 t10 note, which gave this to Ph15) are decided now, for these two enemies.**
  - When a brain is suspended on a rail (`on_suspended()`), it:
    - leaves its squad and turns its `StateLight` off;
    - sets `attack.driven_by_brain = false` and `attack.enabled = true`;
    - installs a pattern equivalent to the legacy weapon, **built from config fields**
      (`rail_*` fields, so the lifetime sweep can read them).
  - `AttackController._process` then self-times the fire.
  - `aim_mode` / `shoot_forward()` / `shoot_at_player()` are now **rail-only inputs**; an AI fighter ignores them.
  - **Ph15 reuses this rule** for every other shooter it takes off rails.
- **Minimal hub idle for the Fighter and the Gatling** (the Ph2 rule was "other families → Ph14"). It is an
  `AnchorIdle` shared ring (IDLE / NOTICING / RETURNING, the Swarm t8d shape), with no bespoke legs. Richer idle stays
  Ph14.
- **Level 1's fighter and interceptor spawns go off rails in Ph3.** Every other level-1 spawn, and every station
  reinforcement, stays on rails until Ph15.
- **The `EnemyPathMover` `"AIStateMachine"` lookup is kept** (Ph1 decision). Its test moves onto a fixture scene,
  because the Light Assault Ship's state machine is deleted.
- **`Steering.lead_target` / `break_contact` are not built.** Lead targeting is `TargetInfo.aim_direction()` /
  `intercept()`. `break_contact` stays with the Sniper (Ph4).
- **`SquadController` gains two data fields and still has no clock:**
  - `convergence_point: Vector2` (`Vector2.INF` = unset). The LEAD writes it every tick while its window is open.
  - `convergence_stage: Dictionary`, member → `0` answered / `1` ready / `2` done.
  - `_reassign()` clears both whenever the LEAD changes, the `attack_window_open` rule. `leave()` erases the leaving
    member's key.
- **Forward fire honours `sprite_forward_angle`**, through one shared static helper,
  **`EnemyMover.sprite_forward_angle_of(node) -> float`** (duck-typed, default `PI/2`). There is no other reader.
  - Patterns fire forward along `Vector2.RIGHT.rotated(rotation + sprite_forward_angle_of(ship))`.
  - `EnemyPathMover` faces with `vel.angle() − sprite_forward_angle_of(actor)`.
  - **Legacy equivalence is angular, not bitwise.** A rotation can differ by 2π from `atan2(−vel.x, vel.y)`. Tests use
    `angle_difference` / `assert_almost_eq`.
  - **`sprite_forward_angle` is the nose direction in the root's frame after `BaseEnemy._rotate_sprite()`'s 180° flip**
    of a child named `AnimatedSprite2D`.
- **Deadline formula for fighters is per entry**, in the existing test's relative form:
  `(entry_time − last_wave_trigger) + engage + deferral + worst_exit + 0.5 < timeout`.
  - `waves_complete` fires **on the tick the last wave triggers**, so delays do not move the clock.
  - `deferral` is the longest attack the budget may not interrupt: fighter `burst_telegraph` + longest burst (0.8 s);
    Gatling `spin_up + sync_wait_max + longest stream` (2.08 s).
  - `worst_exit` is Razor-shaped, from `max_speed`.
  - The drone rows keep Ph2's conservative form.
- **Correction to the research: in-flight enemy bullets never outlive their shooter.** `BulletPool._exit_tree()` →
  `cancel_active()`. So ENEMIES_CLEARED deadlines need **no bullet-flight term**. The side effect is that a leaving
  shooter's bullets vanish mid-screen (legacy did the same). Owner-bound lifetime stays Ph5.
- **Deviation from IDEAS §5.3 ("three … pincer, while a fourth performs a frontal pass"): at most three fighters
  attack at once.** LEAD (frontal) + FLANK_LEFT + FLANK_RIGHT (the pincer). A fourth and later fighters are dry REARs,
  promoted when an attacker dies. Reason: research finding 1's three-attacker cap and the level-1 density gates.

### Names and places (later phases build on these)
- **Fighter:** `assault/scenes/enemies/fighter/` (a `git mv` of `light_assault_ship/`).
  - Classes: `Fighter` (was `LightAssaultShip`), `FighterBrain`, and `FighterConfig` (kept, extended, flat).
  - `WaveBuilder.FIGHTER` / `fighter()` keep their names.
  - `FighterBrain.Phase`: `APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE`, with `IDLE, NOTICING, RETURNING`
    appended.
  - Signals and seams: `phase_changed(new_phase: int)`, `enter_phase()`, `weapon_mode` (read-only), and
    `weapon_mode_changed(mode: int)`.
  - Two controllers: `AimedAttack` (whose pool is `AimedPool`, Pulse, 12) and `ForwardAttack` (`ForwardPool`,
    Scatter, 8). `brain.attack` is the aimed one; `brain.forward_attack` is the second.
  - It keeps its sprite as a single-frame `AnimatedSprite2D` (flipped by `BaseEnemy`).
- **Fighter pass geometry** (plan §2.4.1; other attack-run enemies should reuse this vocabulary):
  - A pass is a bearing `b` (the side it comes from), a run direction `u = −b`, and a lane `l ⟂ u` (the side and the
    distance it passes at).
  - The start point `S = P̂ + b·standoff + l` lies on the pass line, so the closest approach equals `|l|`.
  - RUN_IN is path following with a look-ahead point (it never stalls). It ends when `(P̂ − X)·u < 0`.
  - Pass kinds: FLANK_LEFT/RIGHT-shaped (lanes ahead of the player, `pass_offset` and
    `pass_offset + flank_lane_gap`), FRONTAL (lane to one side of the heading line, alternating), and solo
    (alternates the flank shapes).
  - `left(v) = v.rotated(−PI/2)`, `right(v) = v.rotated(PI/2)` in y-down screen space.
- **Gatling Interceptor:** `assault/scenes/enemies/gatling_interceptor/` (a `git mv` of `interceptor/`).
  - Classes: `GatlingInterceptor`, `GatlingInterceptorBrain`, `GatlingInterceptorConfig`.
  - `WaveBuilder.GATLING_INTERCEPTOR` / `gatling_interceptor()`; `interceptor()` is gone.
  - Phases: `APPROACH, SWING_IN, SPIN_UP, STREAM, COOLDOWN, REPOSITION, DISENGAGE`, with the idle phases appended.
  - It keeps its `Sprite2D` (no flip). `StreamPool` (Gatling Stream, 36).
  - **The Gatling aims its streams at a predicted point.** This settles the "forward or at the player" question; the old
    docs that said "always fires forward" were wrong.
- **The bullet family:** `assault/scenes/projectiles/enemy_bullet/rounds/`, holding `pulse_round.tscn`,
  `scatter_round.tscn`, `gatling_stream_round.tscn` and `heavy_shell.tscn`.
  - They are inherited scenes of `enemy_bullet.tscn`, with no new script, and **one pool per round per shooter**.
  - `EnemyRounds` (`enemy_rounds.gd`) holds the four paths plus `pool_size_for(max_burst, round_lifetime,
    min_burst_period)`. A self-timed rail pattern counts as a burst of 1.
  - `EnemyBullet.reset()` restores the scene's authored speed and damage.
  - **Heavy Shell has no consumer in Ph3.** Its first consumer is Ph4 (Bomber/Ram) or Ph10 (Heavy Gunship).
  - Legacy `enemy_bullet.tscn` stays orange, and legacy shooters keep it until Ph17's audit.
- **`BurstClock`** (`global/enemy_ai/burst_clock.gd`, `RefCounted`) is the one way a brain sequences N shots at a gap.
  - API: `start`, `advance → shots due`, `is_running`, `shots_fired`, `stop`.
  - The brain calls `fire_now()` once per shot due. `AttackController` is unchanged.
  - Later enemies with bursts or salvos (Bomber, Missile Corvette, Gunship) reuse it.
- **Pattern additions:** `AimedAttackPattern.spread_angle`, and on both aimed and Gatling patterns a per-instance
  `rng: RandomNumberGenerator` and `aim_point: Vector2` (`INF` = ask `TargetInfo`).
  - With `rng == null`, the pattern keeps the global `randf`, as legacy does.
  - Patterns stay **built per instance in code**.
- **`WFormation`** (`global/resources/formation/w_formation.gd`) and **`WaveBuilder.w_formation(count, spread, depth,
  stagger)`**, a spawn layout only. Slots zig-zag, with odd slots trailing at `−depth`; spawn order is centre first.
- **Level-1 legacy baselines are frozen constants** in `test_level1_fighter_spawns.gd`: `_LEGACY_PEAK_FIGHTERS` and
  `_LEGACY_PEAK_SHOTS_PER_S`, computed from the live rails in t1 and asserted equal while the rails exist. Any later
  migration (Ph15) freezes its baselines the same way **before** deleting rails.

### Conventions
- **Weapon mode is chosen by distance at each burst opportunity, with hysteresis, and latched for the whole burst:**
  FORWARD below 300 px, AIMED from 360 px, and the last mode in between. It is never a spawn property. **A FORWARD
  opportunity is taken only with the nose within `nose_cone_deg` of the player**; otherwise it is skipped, not spent.
- **Attacker cap without new API:** in a fighter squad, LEAD + FLANK_L + FLANK_R fire and REARs fly **dry** passes. In
  a Gatling squad, LEAD + FLANKs fire and REARs hold.
- **Fighter attack window:** the LEAD opens it on RUN_IN entry and closes it on its EXTEND entry. Flanks answer each
  window once (the Swarm `_answered_window` rule).
- **Side changes:** a fighter's pass is latched at RUN_IN. It takes a new pass kind only through REPOSITION, which never
  seeks a point whose segment passes within `reposition_min_radius` of the player. A member may therefore hold a role
  whose side it is not yet on (`_side_for` can do that).
- **Convergence pairs stay on the same half-plane** of the player, about 40° apart, so the far side stays open. The
  window opens at the LEAD's SWING_IN (both lights CHARGING within one tick). The pair meets in SPIN_UP, capped by
  `sync_wait_max`. The point is refreshed every tick. The window closes on the **later** COOLDOWN entry.
- **No false telegraphs:** the Gatling never enters SWING_IN (CHARGING) with less budget than `swing_in_max` left (the
  Swarm `can_start_attack` precedent).
- **Gatling sides:** the first window takes the current side (Open Space) or the corridor half opposite the player
  (Assault). Every later window flips, except in Assault when the flipped point would be within `min_flank_range` of a
  player hugging a wall.
- **Squads stay per family.** Level-1 loose fighter lines use the id `&"w<n>f"` and Gatlings `&"w<n>g"`. Drones keep
  `&"w<n>"`.
- **Heading reference in Assault is `Vector2.UP`.** Fighter flank and solo passes are lateral runs across the corridor.
  The ahead lane flips behind near the corridor top, and a run shorter than `min_run_length` takes the other bearing.
- **`StateLight`:** CHARGING = the burst telegraph / Gatling swing-in and spin-up; ARMED = firing; OFF otherwise.
  **Neither shooter uses COMMIT** (Ph2 reserved it for committed ram attacks).
- **Pools are sized by formula and pinned for the AI and the rail cadence:**
  `max_burst × ceil(round_lifetime / min_burst_period)`, taking the larger of the two.
  - **Every `BulletPool` is a direct child of the enemy root** (`BulletPool` resolves its container as the
    grandparent).
  - The one exception to "the larger": the rail Gatling keeps the legacy pool-starvation shape (36 in flight, then a
    stall). A true 11 shots/s hose would need 71 and would be a balance change.
- **Round lifetimes are checked against the slowest speed any shooter fires that round at**, read from config fields.
  No speed in the lifetime sweep is hand-typed or regex-read after this phase.
- **Gatlings stay out of ENEMIES_CLEARED sections**, and the deadline test has a boundary row for it, as for the Razor.
- **Level-1 shooter density is gated:** attack-capable ≤ 1.5×, all-alive ≤ 2.0× and shots/s ≤ 1.25× the frozen legacy
  per-section peak. The pre-approved levers, in order: fighter `engage_seconds` 6.0 → 4.5, `assault_passes` 2 → 1, and
  split a formation of 5+.
- **Art tasks keep an enemy's sprite node type and name**, so animation track paths and `test_base_enemy.gd`'s flip
  cases stay valid. Changing a node type means updating all three, and re-deriving `sprite_forward_angle`.

### Deliberately deferred
| Item | Deferred to | Reason |
|---|---|---|
| Heavy Shell gameplay consumer | Ph4 / Ph10 | No in-scope enemy fires it; tested with a fixture shooter |
| Recolouring legacy enemy bullets | Ph17 | Would change every legacy shooter's look |
| Station reinforcements off rails (and the rail Gatling's legacy starvation) | Ph15 | Reuses the rail-fire rule above |
| Cross-squad / cross-family attacker arbitration | Ph14 | Needs squad messages |
| Leash / re-engage for Open Space fighters (they fight indefinitely) | Ph13 | EncounterDirector |
| Muzzle flash, spin-up particles, enemy SFX | Ph17 | `StateLight` is the only telegraph |
| Rotating `spawn_offset` with the nose | Ph17 | 10 px sits inside a 64 px hull |
| `BulletPool` container injection, `persist_after_owner_death` | Ph5 | Unchanged from Ph2 |

### Phase 3, built in t8a (Fighter shell)

- `fighter.tscn` is the AI scene: `Brain` (`FighterBrain`), `EnemyMover` (AUTO), `StateLight`, `AimedAttack` /
  `ForwardAttack` (`driven_by_brain`, disabled). `AimedPool` (Pulse) and `ForwardPool` (Scatter) are direct children of the
  root. `states/` and the `AIStateMachine` are deleted, so **`EnemyPathMover`'s `"AIStateMachine"` name lookup now has no
  subject** (Ph15 can drop it).
- **`AimedPool` is 20, not 12** (review N4): `FighterConfig.min_burst_period` (1.2 s) sizes it, so 5 × ceil(4.67 / 1.2) = 20
  covers the AI burst, the FORWARD rail cadence (12) and the aimed rail cadence (7). The Scatter pool is 8.
- `aim_mode`, `shoot_forward()` and `shoot_at_player()` are **rail-only inputs**, read in `FighterBrain.on_suspended()` and
  nowhere else. The rail speeds and intervals are `FighterConfig` fields (`rail_aimed_speed` 250, `rail_forward_speed` 420,
  `rail_forward_interval` 0.3, plus the legacy `fire_interval` 0.8 and `bullet_damage` 8), and
  `test_enemy_bullet_lifetime.gd` reads them; the regex over `fighter.gd` is gone.
- `test_level1_fighter_spawns.gd` reads a fighter's rate through `suspend_ai()` on `AimedAttack` / `AimedPool`, so the frozen
  legacy constants still hold unchanged (rail fighters fire the same cadence, now with Pulse rounds).

### Phase 3, built in t8b (Fighter attack runs)

Task plan: `docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md` (revision 2, approved with binding notes I1–I8 in
`4-review.md`). The epic's §2.4.1 geometry (`b`, `u = −b`, `l ⟂ u`, `S = P̂ + b·standoff_radius + l`) and §2.4.2
weapons are built as the epic wrote them. The deviations later phases depend on:

- **New shared class `DubinsPath`** (`global/enemy_ai/dubins_path.gd`, pure `RefCounted`): the shortest
  turn-radius-limited path between two poses, all candidates sorted by length. APPROACH and REPOSITION are Dubins lead-ins
  to S that arrive pointing along the run, planned at 1.1 × the turn radius and tracked with `turn_toward`. The first
  candidate whose 16 px samples clear the player's predicted positions wins. Ph4's attack-run enemies (Bomber, Ram) can
  plan with it.
- **TURN ≠ the epic's "turn toward S".** Its first step is a full-rate turn back toward the player until the nose is on
  it (opportunity (b), the snapshot, capped at a full circle, I4). It then flies a break-away: the REPOSITION path's first
  arc, with a 120 px clearance on that arc only, or a peel when no path exists. REPOSITION flies the rest of the path,
  outside `reposition_min_radius`. The literal epic rule was degenerate for the solo alternation (review N8), and it never
  brought the nose on the player, so FORWARD never fired.
- **`forward_range` 300 → 325** (the epic's K5 lever): the snapshot comes nose-on at ≈ 220–305 px. Hysteresis is still
  60, so the acceptance numbers 250 / 400 / 330 are unchanged.
- **APPROACH clearance and breach radius come from S:** clearance = `min(standoff, |S − P̂|) − 1`, breach radius = that −
  24 px. A breach, or the APPROACH/REPOSITION **deadline**, starts a FRONTAL-shaped pass from the current bearing, with
  its lane ⟂ the new `u` on the drift side (N9). The deadline is (the remaining length of the first plan in that phase) /
  `max_speed` + `reposition_max` (I1).
- **P̂'s lead is latched at RUN_IN entry** together with `b`, `u`, `l` and the kind, and released at EXTEND's end. Before
  RUN_IN the pass is re-derived every tick. RUN_IN feeds forward the lane's sideways velocity, and the handover heading is
  the run heading `g` (`u` for a holding player).
- **Re-planning follows S's predicted track** (`S_plan + v_P·age`), not S's distance from where it was at plan time. The
  literal rule re-plans every ≈ 0.12 s against a moving player (I5's measurement). The arrival prediction
  `T = length(S + v_P·T) / max_speed` is refined three times, capped at 3 s.
- **Assault:** h = UP. S is clamped along the run axis into `inner_rect()` shrunk by `2 × 1.1 × turn radius + hull`. A
  flank lane under the corridor top flips behind, and a FRONTAL lane at a side wall flips σ. The bearing flips when the run
  would be shorter than `min_run_length`. EXTEND ends when the point 0.3 s ahead leaves `inner_rect().grow(−hull)`, and the
  ring fallback clamps 200 px inside the rect (I7, the prototyped rules). The turn-in takes the long way when only that
  circle fits.
- **Weapons:** the FORWARD burst holds the nose (rotation, via `mover.face_toward`) on the player, never the path. The
  shot bearing runs up to ≈ 1.75 rad/s, under the mover's 1.8 cap, and the distance still falls to ≈ 150–200 px (I3).
  `min_burst_period` is enforced between burst starts. Opportunity (b) is TURN-only.
- **New config fields:** `run_in_max` 4.0 and `regroup_seconds` 1.5 (Tactics).
- **Seams for t9:** `forced_pass_kind` (≥ 0 gives every pass that kind, with FLANK_RIGHT's role-shaped outer lane), the
  read-only `pass_*` fields, `passes_done`, and the Open Space loiter at S.
- **For t16 (I8, and task-plan deviation 8):** at `engage_seconds` 6.0 an Assault fighter flies exactly one lateral pass
  with one AIMED burst and leaves during EXTEND. So it **never fires FORWARD in Assault**, and the lever
  "`assault_passes` 2 → 1" changes nothing today. The epic's "in Assault FORWARD is more common" does not hold.
- **Moving player (I6):** against a player cruising at 200 px/s the fighter closes at ≈ 100 px/s along the course, and
  REPOSITION rarely reaches a moving S before its deadline. The steady state is a breach-shaped pass about every 15 s,
  none touching the player. From abeam or behind, the first pass comes from APPROACH's deadline at 5–11 s.
  `test_fighter.gd`'s natural-play case spawns ahead-and-beside the course. A holding player gets a flank pass about
  every 10 s.

### Phase 3, t9 (fighter squads): escalated, nothing built (2026-09-30)

Findings: `docs/plans/cmulwkar300bxqj2xgtk6jyu3/5-escalation.md`. The fighter code is unchanged (t8b), and both measured
variants are kept as patches in that task's `prototype/`. What later tasks need to know now:

- **§2.5's "`flank_stagger` is the one separation fix" does not hold.** 271 of the 290 failing runs in a 420-layout sweep
  are closest within 2 s of spawn: the formation fans out from 80 px slots before any run exists to stagger. Today's t8b
  formations (independent solos) already overlap in 293 of 420 layouts. Only a reactive avoidance layer (ORCA, measured
  5/420) met the criterion. That is a scope change awaiting the owner.
- **The Assault budget (6.0 s) does not fit a pincer rendezvous.** A flank can reach its S too late for any run to fit before
  expiry. At the shipped budget, 3 of 18 Assault squads leave an attacker silent even with no avoidance at all, and lever 1 (→ 4.5 s) would
  make most squads silent. t16/t17 must not assume squads fight in Assault until the owner decides.
- **Fighter bodies physically collide with each other** (layer 1 "environment", mask 1). In a hand-ticked GUT run that
  collides with mates' unstepped spawn positions and makes a squad simulation non-deterministic. Any squad test needs
  `add_collision_exception_with()` between members.
- **t8b's ring fallback** (`_fly_ring`) seeks chords that pass 231–249 px from the player, inside
  `reposition_min_radius` (288). The acceptance line's seek-target rule needs the tangent cap the prototypes carry.

### Phase 3, t9 (fighter squads) round 2: blocked, still nothing built (2026-10-05)

Findings: `docs/plans/cmulwkar300bxqj2xgtk6jyu3/5-escalation.md` → "Round 2". The fighter code is unchanged (t8b +
t10). Revision 2 (in-scope give-way, no ORCA) is kept as `prototype/revision2_variant.patch`. What later tasks need:

- **Without ORCA, the first attack window can be made clean.** A holder stepping off a moving mate's planned track, a
  member on a lead-in slowing along its own track for attackers, and "only a member settled on its S answers a window"
  gave 0 in-cycle overlaps in 168 layouts (V3/W5, both modes), with no breach passes. Routing lead-ins round mates was
  measured and made breaches and silence worse.
- **The REARs' dry passes are the unsolved part.** Over a full two-pass cycle a W5 overlaps in 35 of 42 Open Space
  layouts (worst 3.5 px): a REAR's dry-pass TURN against an attacker's TURN in the second window. TURN does not give
  way, and `flank_stagger` only spaces run starts. A level formation with REARs (more than three fighters) is not
  separation-safe until this is designed.
- **Still open for the owner, and t16/t17 must not assume either:** whether the separation criterion covers a full
  cycle or the first window only; the Assault budget (with the rendezvous, 7 of 84 Assault layouts leave a flank that
  holds and leaves without firing — a flank that crossed most of the corridor); fighter body collision.
- **Spawn fan-out is the spawn layout's problem (t16):** from 80 px slots, 19 of 168 layouts still overlap before the
  first window even with the give-way.

### Phase 3, built in t10 (Gatling Interceptor pressure windows) (2026-10-05)

Task plan: `docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md` (approved, with binding notes A1–A8 in `4-review.md`). The
epic's §2.6 solo Gatling and its §2.8 rail fallback are built as written, except as follows. Later tasks depend on these.

- **Scene and names.** `gatling_interceptor.tscn` keeps every legacy node and gains:
  - `EnemyMover` (AUTO), `Brain` (`GatlingInterceptorBrain`) and `StateLight`;
  - `StreamPool` (Gatling Stream, 36), a root child;
  - `Attack`: the one `AttackController`, `driven_by_brain`, disabled.

  The stream pattern is built per instance in `gatling_interceptor.gd`, with the brain's `rng`. `aim_point` stays INF.
  That is t11's hook.
- **Config renames.** The legacy weapon fields `fire_interval` / `bullet_speed` / `spread_angle` / `bullet_damage` are
  now `rail_stream_interval` / `rail_stream_speed` / `rail_spread` / `rail_damage`. The AI stream is `round_speed` 240,
  `round_damage` 4, `stream_spread` 0.05 and `accuracy` 0.8. `test_enemy_bullet_lifetime.gd` reads `round_speed` and
  `rail_stream_speed`, so no speed in the sweep is hand-typed or regex-read.
- **Deviation (task plan D2): a swing to the other flank does not fit in REPOSITION 1.0–1.5 s + SWING_IN ≤ 1.5 s.** The
  shortest route that keeps clear of the player is ≈ 891 px (3.4 s at 260 px/s), and round the ring it is ≈ 970 px.
  - REPOSITION now lasts at least its rng 1.0–1.5 s **and** until the new `F` is within the new `swing_in_reach` (300 px),
    capped by the new `reposition_cap` (5.0 s).
  - APPROACH hands over on the same reach rule, or after `reposition_cap` once within `preferred_range + approach_margin`
    (new, 250).
  - Every epic rule is unchanged: CHARGING only in SWING_IN + SPIN_UP and always followed by a stream, SWING_IN only with
    `swing_in_max` of budget left, and SWING_IN ≤ `swing_in_max`.
- **Routing and strafe.**
  - Swings step round the 380 px ring, 50° at a time, never across the player.
  - In Assault they go round **ahead** of the player, except that a route the corridor clamp would pull within
    `min_flank_range` goes round behind (review A2, test seam `route_fallback`).
  - In Open Space they take the short way.
  - The strafe in SPIN_UP / STREAM / COOLDOWN continues the arrival velocity (A1). It runs at `stream_strafe_speed` with
    a range-holding correction, and the player's velocity is fed forward.
- **Sides.**
  - **First window:** APPROACH re-derives the side every tick and latches it on exit (A3).
  - **Later windows:** REPOSITION entered from COOLDOWN flips the side. In Assault the flip is skipped when the flipped
    `F` is within `min_flank_range` of the player horizontally.
- **For t16 (A7). Read this before tuning level 1.**
  - The average window period is ≈ 5.8 s (≈ 1.7 shots/s), against the epic's ≈ 2.8 s (≈ 3.5 shots/s).
  - The *minimum* period, `GatlingInterceptorBrain.min_window_period()` = 2.28 s, is shorter than the epic's 2.8 s. It
    is reachable in the Assault wall case, where there is no swing.
  - So a shots/s numerator of `max_rounds / min_window_period()` gives 5.26 shots/s per Gatling, against the epic's
    12 / 2.8 = 4.29. "Lower density" holds on average only, and t16 must choose which bound its gate uses.
  - **An Assault Gatling at `engage_seconds` 7.0 usually gets one window before it leaves**, so R3.7's "attacks from the
    other side" is rarely seen in Assault. The owner should see this when t16 tunes `engage_seconds`.
- **For t11 (A7).**
  - `min_window_period()` bounds `StreamPool` (36) only if every path into SWING_IN passes REPOSITION's minimum. A FLANK
    that answers a window from COOLDOWN skips it. The period then drops to ≈ 0.9 s, and the need to
    12 × ceil(5.83 / 0.9) = 84, so 36 would starve silently.
  - t11 must answer only from REPOSITION after its minimum, or recompute the pool assertion.
  - A FLANK entering SWING_IN directly bypasses the `swing_in_reach` gate. That is acceptable: `swing_in_max` still caps
    it.
- **Level-1 frozen constants (A4).** `test_level1_fighter_spawns.gd` now suspends every ship that has a `Brain` before
  reading its rail stats, and reads each ship's round range from its own pool's round (Pulse or Gatling Stream, 1400 px),
  not the legacy 2400 px bullet.
  - All three frozen sections still equal their constants. deep_space's Gatling pair is outside its peak window, and the
    fighters are capped by their interval.
  - No constant was re-frozen. If a later change pulls the pair into a peak, freeze the legacy interceptor's inputs
    (pool 20, 2400 px round, 220 px/s, 0.09 s) as constants, per B6. Do not derive a delta.

### Phase 3, built in t11 (Gatling convergence fire) (2026-10-05)

Plan §2.6.1 (Revision 2) as written, with these differences. `GatlingInterceptor` gains `var squad: SquadController`
(joined in `_ready()` like the Fighter's), and `GatlingInterceptorBrain` the convergence logic. Tests:
`tests/integration/test_gatling_convergence.gd`.

- **"Ready" is stage 1 set when the member's *own spin-up has elapsed*, not on SPIN_UP entry.** With entry-based
  readiness the early shooter streams as soon as its partner *enters* SPIN_UP, 0.25 s before the partner can stream,
  so the §4 acceptance "STREAM starts within one tick" cannot hold. The bounded wait is unchanged: at most
  `spin_up_seconds + sync_wait_max` after reaching SPIN_UP.
- **Only APPROACH, COOLDOWN and REPOSITION FLANKs answer** (review N3); a FLANK in its own SWING_IN / SPIN_UP / STREAM
  skips the window, and so does a far one — a FLANK decides once per window (`_answered_window`, reset on reading it
  closed), whether it joins or not.
- **The FLANK takes the LEAD's `side`, read from the LEAD's brain** (`members()` / `role_of()`, no SquadController
  API), so a second window's FLANK follows the LEAD's REPOSITION flip even before the LEAD has crossed. Its flank
  point is the LEAD's, rotated toward the heading; when the Assault corridor clamp leaves it < 30° from the LEAD's,
  it is rotated the other way instead.
- **A LEAD holds in REPOSITION while a window it owns is open** (`can_start_window()` gained that term), at most
  one stream long.
- **Not built (t12+ / later):** a REAR Gatling keeps its own rhythm — §2.6.1's "REARs hold at `preferred_range + 200`
  and never fire" is not implemented, so a third Gatling in a squad fires solo windows. Nothing places three Gatlings
  in one squad before t16, which should decide whether it is needed.
- **Config:** `GatlingInterceptorConfig` gains `convergence_bearing_offset_deg` 40, `convergence_aim_error_deg` 3,
  `convergence_join_range_factor` 1.5 (all [judgement], from the plan).

### Phase 3, built in t9 (fighter squads), Revision 3 (2026-10-05)

Supersedes the two "t9 … nothing built" sections above where they differ.
Task plan: `docs/plans/cmulwkar300bxqj2xgtk6jyu3/3-plan.md` (Revision 3; review history in `4-review.md`). The task was
re-queued after round 2 with no recorded owner decision, so it took escalation option (a), the reviewer's own reading:
**separation is asserted over a full cycle** (Open Space: every window up to and including the first one each REAR
flies a dry pass on), which relaxes nothing. Later tasks depend on these.

- **Names.** `Fighter.squad: SquadController` is the duck-typed slot `WaveManager` (and later `SectorHub`) writes
  before `add_child`; `Fighter._ready()` joins it (epic "on its first tick" → `_ready()`, the Swarm precedent). A
  fighter leaves the board on DISENGAGE entry and on a rail (`on_suspended()`). `FighterBrain.PassKind.REAR` is new.
  `FighterConfig` gains `lead_wait_max` 3.5 and `flank_stagger` 0.4, and `rear_standoff_radius` / `flank_wait_max` are
  now read. Duck-typed brain queries mates read: `is_holding()`, `is_settled()`, `is_on_pass()`,
  `is_braking_onto_station()`, `predicted_position(t)`, `squad_priority()`, `run_budget_slack()`, `pass_role`.
- **Deviations from epic §2.5.**
  - **REAR spacing:** each REAR has its own lane, one `flank_lane_gap` further out per `rear_index`, on a side latched
    when it becomes REAR; `rear_count` is unused (not a ring spaced by `rear_index/rear_count`).
  - **The latch** (`pass_role`, `b`, `u`, `l`, kind) is set at RUN_IN entry and released at EXTEND's end (t8b's TURN
    re-derives the next pass), not "until the next REPOSITION". TURN's break-away is the one exemption from the
    seek-target rule.
  - **Every member holds at its S** (the LEAD too, until its flanks settle or `lead_wait_max`); only a member *settled*
    on S (within 32 px, slow) answers a window or counts as ready.
  - **`flank_stagger` is generalised** to the crossing time of any two runs (and a one-gap trail for parallel same-way
    runs), not only "FLANK_RIGHT's start".
  - **Separation needs more than `flank_stagger`** (the only fix the epic pre-approved): a holding member slides off a
    moving mate's planned track, a member on a lead-in slows along its own track (and, when no speed keeps clear, slides
    aside from a mate on a pass). Round 2 ruled these within the task's discretion: brain-local, no shared API, no
    heading-source change, RUN_IN/EXTEND/TURN/DISENGAGE never give way.
  - **REAR dry passes have their own slot** ("every other cycle" made concrete): in Open Space a REAR becomes due on
    every second window and flies after that window closes, once no mate is on a pass and every attacker holds; the
    LEAD's next window and a FLANK's `flank_wait_max` run wait for it. **In Assault a REAR never dry-passes**: an
    Assault fighter leaves after `passes` passes, so REARs are reserves promoted as the attackers leave.
  - **A hold off S is bounded:** a member unsettled for 2 × its own wait goes anyway (no endless Open Space hold).
- **Still open for the owner — not decided by this task:**
  - **Decision 2, the Assault budget.** At the shipped 6.0 s, 7 of 84 dense Assault layouts leave one flank that
    crossed most of the corridor holding at S and leaving without firing (the build's current handling, "a late flank
    holds and leaves", is the default, not a decision). A longer budget is not separation-safe yet: with two passes,
    V3 fails 13/42 and W5 25/42 (worst 0.9 px — flank turns converging in the corridor, and a LEAD/FLANK station swap
    after a member leaves). Lever 1 (→ 4.5 s) would silence most squads.
  - **Decision 3, fighter body collision** (layer 1, mask 1). Squad tests except collision between mates.
- **Gaps left for later tasks (measured, `3-plan.md` §Measurements):**
  - **After a death** `SquadController._reassign()` recomputes every role by distance, which can swap two members'
    stations or leave a mid-pass squad with a new LEAD whose turn meets a flank's turn; separation is not asserted
    there and fails in up to 9 of 42 W5 layouts (worst 7.3 px, V3). A post-reassignment resync is a follow-up.
  - **V6** fails 1 of 42 in Open Space (a third REAR); V4 is clean; line4 was not measurable (its stagger awaits a
    timer). t16 must re-run separation on whatever formations it ships.
  - **Spawn fan-out** before the first window (19 of 168 layouts, measured for Revision 2) is t16's spawn-layout problem.
  - **`_mates()` scans the `enemies` group** per tick; fine at V3/W5, revisit for larger squads.

### Phase 3, built in t12 (Fighter and Gatling hub idle) (2026-10-06)

- **Shape:** both brains append `IDLE, NOTICING, RETURNING` (Fighter 6/7/8, Gatling 7/8/9) and use the Swarm's `AnchorIdle`
  meta-state. `patrol_anchor` and `start_engaged` are brain fields (the hub, t13, sets `patrol_anchor` on the brain before
  `add_child`); the radii live on the config: `perceive_radius` 540 / 560, `lose_radius` 900, `notice_time` 0.35,
  `idle_radius` 150, `idle_speed` 0.5 (Fighter / Gatling) **[judgement]**.
- **Deviation from the Swarm shape:** the Swarm defers only RETURNING while it bursts. Here **IDLE and NOTICING are deferred too**
  (fighter: while `is_bursting()`; Gatling: while `is_in_window()`, so a yellow light is always followed by its stream).
  Without it a shooter already near its anchor goes COMBAT → RETURNING → IDLE in one burst and keeps firing from IDLE.
- `idle_phase_offset` is drawn in `_start()` only when idle begins, never in `_ready()`, so seeded combat sequences are unchanged.
- Every earlier fighter/Gatling test spawns through a helper that sets `start_engaged`; new cold-start cases are at the end of
  `test_fighter.gd` and `test_gatling_interceptor.gd`.

### Phase 3, built in t13 (hub patrol: fighter pair + Gatling pair) (2026-10-06)

- `SectorHub._spawn_patrol()` adds a fighter squad of 2 and a Gatling squad of 2 (`SHOOTER_SQUAD_SIZE`), each sharing one
  `SquadController` and one `patrol_anchor` set on the brains before `add_child`. Exports: `shooter_ring_radius` **1500**,
  `fighter_anchor_bearing_deg` **180**, `gatling_anchor_bearing_deg` **0** — the plan's starting values, **unchanged**: the
  generic sweep accepted them, so no bearing or ring was moved.
- **Computed clearances** (nearest `MissionTrigger` / `PickupBase` / player spawn; `idle_radius` 150 for both):
  fighter anchor (−1500, 0): nearest `LoreLogFortunaManifest`, 922.8 px → 772.8 after the ring → **+232.8** over `perceive_radius` 540.
  Gatling anchor (1500, 0): nearest `ShipBoostUpPickup`, 798.7 px → 648.7 → **+88.7** over `perceive_radius` 560. These match the
  plan's estimates (233 / 89). The Gatling's 89 px is thin but positive; a pickup added within ~89 px less will fail the sweep.
- Shooter rng seeds are drawn after the drones', so the Swarm and Razor seeds for a given `patrol_seed` are unchanged.
- `test_sector_hub_patrol.gd`: per-group counts replace the total-child-count assertion; clearance rows for both new groups;
  shared anchors, frame-0 IDLE, and a fighter Pulse / Gatling round landing in `EnemyContainer`.

### Phase 3, t16 (level 1 deep_space / planet_approach off rails): escalated, nothing built (2026-10-06)

Findings: `docs/plans/cmulwkarm00cpqj2xfwq3ue8h/5-escalation.md`. The level and the t1 pin are unchanged; the mechanical
level edit is kept as `prototype/level1_duration_rails_off.patch`. What later tasks need to know now:

- **The epic §2.9.2 shots/s gate cannot pass with the pre-approved levers.** With the plan's numerator (fighter 7 / 1.55
  = 4.52, Gatling 12 / 2.8 = 4.29 shots/s per attack-capable ship) deep_space computes 58.25 against a 39.06 limit
  (1.86×) and planet_approach 63.23 against 41.67 (1.90×). Lever 1 leaves deep_space unchanged (its peak is set by
  overlapping *spawn times*), lever 2 changes nothing (the budget bounds the lifetime), lever 3 raises the attacker
  count. The all-alive (≤ 2.0×: 17, 16) and capable (≤ 1.5×: 13, 14) gates pass.
- **The AI is much quieter than the analytic model says.** A real run (stationary player) fires 114 shots in each
  section against the rails' 524 / 1029; peak shots/s over 2 s is 12.0 / 6.5 against the rails' 31.0 / 35.0 (which
  reproduce the frozen constants). An Assault fighter fires about one burst per life.
- **Awaiting the owner:** which shots/s check replaces or relaxes the analytic one (options A–E in the escalation; A, a
  measured real-run check, is recommended). t17 (cloud_descent) will meet the same gate shape.
- **Separation in the shipped formations** (the t9 note): closest approach 50.4 / 54.0 px against a 57.2 px hull
  diameter — brief contacts. Not gated.

### Phase 3, t16 (level 1 deep_space / planet_approach off rails): built with the owner's option A (2026-10-06)

Plan: `docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md` (Revision 2, independent review round 2 APPROVED). This supersedes
the "escalated, nothing built" note above.

- **Level edit as epic §2.9.2.** In `_build_section_1()` and `_build_section_2()`, every fighter line lost `.move()`,
  `.free_after()` and `shoot_*()`. The deep_space pair is `gatling_interceptor()` `squad(&"w0g")`. Loose pairs are tagged
  `w9f w20f w22f w27f` (deep_space) and `w11f w18f w24f w30f` (planet_approach). **Lone loose fighters stay untagged
  on purpose:** `WaveManager` keys them as a squad of one either way, which is the Ph2 lone-drone convention. Triggers,
  offsets, delays and formations are unchanged, as the pin shows.
- **Owner decision, option A: the shots/s gate is measured, not computed.** The epic's analytic shots/s figure is
  printed but not asserted. `tests/integration/test_level1_fighter_fire_density.gd` (**new intent test; t18: add it to
  the CLAUDE.md gate paragraph**) runs each section's fighter and Gatling entries through a real `WaveManager`, with
  every wave kept in list order and a stationary player stub. It counts every `EnemyBullet` entering the container and
  asserts that the peak shots in any 2 s window ÷ 2 is at most 1.25 × the frozen `_LEGACY_PEAK_SHOTS_PER_S`. Every brain
  is seeded from its spawn index (`EnemyBrain.rng_seed`), so this is one seeded scenario. The run is sped up 4× with the
  physics step held at 1/60 s: `time_scale`, `physics_ticks_per_second` and `max_physics_steps_per_frame` are scaled
  together and restored in `after_each`.
  - Measured: deep_space **9.0** shots/s (limit 39.06; 110 shots, 90 fighter + 20 Gatling) and planet_approach
    **6.5** (limit 41.67; 118 shots).
  - Analytic, printed only: 60.2 and 63.2. The Gatling rate now reads the brain's `min_window_period()` instead of the
    plan's typed 2.8 s.
- **Count gates (analytic, asserted) divide by the frozen `_LEGACY_PEAK_FIGHTERS`.**
  - All-alive: 17 and 16, against a limit of 20.
  - Attack-capable (first 3 per fighter squad, first 2 per Gatling squad): 13 and 14, against a limit of 15. The
    `min(alive, cap)` model gives the same values and is printed alongside.
  - Lifetimes are read from the configs: fighter 9.64 s (engage 6.0 + deferral 0.8 + Razor-shaped exit), Gatling
    12.0 s.
  - Shared helpers in `tests/helpers/level1_drone_concurrency.gd`: `squad_key()`, `shooter_squad_intervals()`,
    `ai_shooter_kinds()`, `worst_exit_after_speed()`, `peak_min_alive_cap()`, `capable_peak_time()` and
    `peak_window_rate()`. `test_engagement_deadline.gd::_razor_deadline` now calls `worst_exit_after_speed()`, with the
    same arithmetic. **t17 should reuse all of these**, including the measured gate for cloud_descent (legacy 15.0).
- **No lever used.** `engage_seconds` stays 6.0, there is no `assault_passes`, and no formation is split.
- **The pin:** the 37 rows are AI rows (`movement` false, `free_after` 0, `aim_mode` ""). The live-equals-constant
  check now runs for `_RAIL_SECTIONS = [cloud_descent]` only; t17 retires it. The constants themselves are unchanged.
- **Superseded epic §4 boundary.** "A 3rd Gatling added to deep_space's pair pushes shots/s over" was written for the
  analytic figure option A removed, and a third Gatling cannot move the measured ≈ 9 past 39. Its replacements:
  - `test_peak_window_rate_rejects_a_dense_burst` shows the shots/s gate can reject;
  - `test_extra_formations_at_the_peak_break_the_count_gates` shows the count gates can: a V3 added at
    planet_approach's capable peak gives 14 → 17 > 15.
- **Wave-order quirk, found and not fixed (triggers are pinned).** `WaveManager` triggers strictly in list order. In
  deep_space, the 2.0 s V5-fighter wave and the 3.0 s drone wave are listed after the 3.5 s gunship wave, so in the game
  both trigger at **3.5 s**. The measured run reproduces this (`test_waves_trigger_on_the_shipped_schedule`). The
  analytic count gates, the frozen constants and the Ph2 drone pin all model them at 2.0 s and 3.0 s. That is
  consistent with their own denominators, but differs from the game by up to 1.5 s.
- **Known gaps:** one scenario (stationary player). A moving player is not measured. No human playtest.

### Phase 3, built in t17 (level 1 cloud_descent off rails) (2026-10-06)
Task plan `docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md` (Revision 2; review `4-review.md`).
- **Level:** all 27 cloud_descent fighter lines lost `.move()` / `.free_after()` / `shoot_*()`; triggers, offsets, delays
  and formations unchanged. Loose lines sharing a wave are tagged `w<raw_waves index>f` (`w2f w5f w8f w12f w13f w15f
  w20f w22f`); the 59 s wedge and the 72 s V3 are formation squads. **Nothing in level 1 flies a fighter or Gatling rail
  any more.** No lever used.
- **The pin:** `_RAIL_SECTIONS` is empty; the frozen constants are untouched (cloud_descent 8 / 15.0) and a new
  assertion requires every frozen key to be live-checked or divided by a gate. `MIGRATED_SECTIONS` has all three
  sections. Count gates for cloud_descent: all-alive 9 ≤ 16, attack-capable 8 ≤ 12. Measured shots/s 8.5 ≤ 18.75.
- **Deviation from the task wording — the fighter deadline's exit term is a curved-exit bound, not Razor-shaped.**
  `FighterBrain._tick_disengage` turns the *velocity* toward its exit point at ω = min(turn_rate, acceleration /
  exit_speed) = 1.346 rad/s while asking for `exit_speed`, so a fighter flying away from its exit swings round on a
  ≈ 386 px radius. Measured on the real `fighter.tscn`: **4.87 s** from the rect centre heading away; the Razor-shaped
  straight-line term says 2.84 s; just above the standing-start threshold (91 px/s) it is **5.20 s**. `test_engagement_deadline.gd` now uses `π/ω + (exit_distance + 2·exit_speed/ω) /
  exit_speed` = **5.37 s** and gates it on the real scene (`test_the_fighter_exit_term_bounds_a_real_fighters_disengage`,
  404 starts: grid × headings × {max_speed, standing-start threshold + 1}; real slack 0.17 s). Per-entry result: worst entry 72.8 s → 9.47 s of the 10 s timeout, **margin 0.53 s** (the straight-line
  figure would have reported 3.06 s). The Gatling boundary row keeps the Razor-shaped term (it must fail; a longer real
  exit only fails it harder).
- **Owner item, not changed here:** `DroneConcurrency.ai_shooter_kinds()` — the t16 count gates' fighter lifetime —
  still uses the straight-line exit (9.64 s). With the curved bound (≈ 12.2 s) the task reviewer measured deep_space's
  all-alive peak at **21 against t16's limit of 20**. Correcting it is t16's gate and needs the owner's call (a lever, or
  accepting the measured 11.67 s life, which gives 18). The Ph2 Swarm/Razor deadline formulas also assume a straight
  exit; whoever owns them should check the drones' curved exit the same way.
- **Real run:** `tests/integration/test_level1_fighter_exit.gd` replays cloud_descent from 66.0 s (re-timed) through a
  real `WaveManager` with a stationary stub player at 1×. Container empty **9.07 s** after `waves_complete` (margin
  0.93 s — set by the 76 s Swarm drones, as in Ph2's own run) and the last fighter gone 4.35–5.12 s after it, every
  fighter in DISENGAGE with no `EnemyPathMover`. "waves_complete fires on the last trigger" is judged on `WaveManager`'s
  own idle-delta clock: the summed physics clock can lag it by the first frame's set-up hitch (0.12 s seen once).

## Phase 3 - as built (2026-10-07)

All 18 build-sequence keys of `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` (**Revision 2**) landed on
`agent/auto-dev`: t1–t7, t8a/t8b, t9–t17, plus this t18. Preparation was research → plan (Revision 1, owner
CHANGES_REQUESTED on B1–B6 and ten should-fix points) → Revision 2 (round-2 review APPROVED with notes N1–N12, all
applied). Five build tasks (t8b, t9, t10, t16, t17) were planned and independently reviewed on their own — t9 and t16 first
ended a run escalated with nothing built, and t9 was re-planned three times — each has a task plan directory under
`docs/plans/cmulwkar…/` with its own review. `docs/epics-done/cmufs7ekv000lnm2x7nbswijy/`
holds the dossier (PRD / SOURCES / REPORT). The per-task "built in tX" notes above are the detail; this section is the
index a later phase should read first. **Where a per-task note and this section differ, this section wins.**

### What was actually built

- **The bullet family.** `assault/scenes/projectiles/enemy_bullet/rounds/` — `pulse_round.tscn`, `scatter_round.tscn`,
  `gatling_stream_round.tscn`, `heavy_shell.tscn` (inherited scenes of `enemy_bullet.tscn`, no new script) and
  `EnemyRounds` (`enemy_rounds.gd`: the four scene constants + `pool_size_for`). `EnemyBullet` gained `_authored_speed` /
  `_authored_damage` so `reset()` restores *the scene's own* identity. The Heavy Shell has a second `Line2D` (`Rim`).
  The Scatter round has a 2 px circle hitbox and a 450 px range.
- **Shared AI machinery** (all pure `RefCounted` or static; none moves a node, so all pass the single-writer gate):
  `BurstClock` (`global/enemy_ai/burst_clock.gd`), `DubinsPath` (`global/enemy_ai/dubins_path.gd` — **not in the plan**,
  see deviations), `EnemyMover.sprite_forward_angle_of()` (static, the one reader), and the `SquadController`
  `convergence_point` / `convergence_stage` fields. `AimedAttackPattern` / `GatlingAttackPattern` gained `rng`,
  `aim_point` and (aimed) `spread_angle`; their forward branch fires along the nose. `Swarm` and `Razor` brains'
  `_facing()` were migrated to the shared reader (review N2).
- **`WFormation`** (`global/resources/formation/w_formation.gd`) + `WaveBuilder.w_formation(count, spread, depth,
  stagger)`.
- **The Fighter** (`assault/scenes/enemies/fighter/`, a `git mv` of `light_assault_ship/`): `Fighter`, `FighterBrain`
  (1642 lines), flat `FighterConfig`. `states/` and the `AIStateMachine` deleted. Attack runs, weapon selection by
  distance, squads (LEAD frontal + two flank lanes + dry REARs), Assault DISENGAGE, hub idle, rail fallback.
- **The Gatling Interceptor** (`assault/scenes/enemies/gatling_interceptor/`, a `git mv` of `interceptor/`):
  `GatlingInterceptor`, `GatlingInterceptorBrain`, flat `GatlingInterceptorConfig`. Pressure windows, side-on flank
  point, swing to the other flank, convergence fire for a pair, hub idle, rail fallback.
- **Art.** `fighter.png` (new, 64×64: dark hull, pale-blue edge light, red stripe, twin engines) and a redrawn
  `interceptor.png` (64×64: wide wing pods and a three-barrel rotary cannon). Each keeps its sprite node type and name
  (`AnimatedSprite2D` for the Fighter, flipped by `_rotate_sprite`; `Sprite2D` for the Gatling).
- **Open Space.** `SectorHub._spawn_patrol()` adds a fighter pair and a Gatling pair on a 1500 px ring (anchors at 180° and
  0°), each sharing one `SquadController` and one `patrol_anchor`.
- **Level 1.** All 64 fighter / Gatling lines (62 fighters + the deep_space Gatling pair; 18 + 19 + 27 per section) are AI
  spawns: no `.move()`, `.free_after()` or `shoot_*()`. Triggers, offsets, delays and formations are unchanged and pinned.
  **Nothing in level 1 flies a rail of these two any more.** Only the station's TOP/LEFT/RIGHT reinforcements still do.
- **Gates added or extended:** `test_enemy_rounds.gd`, `test_enemy_bullet_lifetime.gd` (round sweep),
  `test_level1_fighter_spawns.gd` (pin + count gates), `test_level1_fighter_fire_density.gd` (measured gate),
  `test_level1_fighter_exit.gd` (real `WaveManager` run), `test_engagement_deadline.gd` (fighter rows, Gatling boundary,
  real-scene exit probe), `test_station_reinforcements.gd::test_rail_reinforcements_fire`, and the behaviour specs
  `test_fighter.gd`, `test_fighter_squad.gd`, `test_gatling_interceptor.gd`, `test_gatling_convergence.gd`,
  `test_wave_builder_formations.gd`, `test_burst_clock.gd`, `test_dubins_path.gd`, `test_attack_patterns_forward.gd`.

### Deviations from `3-plan.md` (every one that a later phase can depend on)

| # | Plan said | What was built | Why / consequence |
|---|---|---|---|
| 1 | §2.2: `AimedPool` 12 | **20** | Review N4: a `min_burst_period` of 1.2 s (new `FighterConfig` field, enforced by the brain) makes the Pulse AI need 5 × ceil(4.67 / 1.2) = 20. The rail cadences fit inside it. |
| 2 | (no such class) | **`DubinsPath`** | A pass geometry that is correct on paper needs a turn-radius-limited lead-in that arrives pointing along the run (review B1, N8). Reusable by Ph4's Bomber/Ram. |
| 3 | §2.4: TURN "turns toward S" | TURN first turns **back onto the player** (opportunity (b), the snapshot), then flies a break-away arc | The literal rule was degenerate for the solo alternation and never brought the nose on the player, so FORWARD never fired. |
| 4 | `forward_range` 300 | **325** (the epic's K5 lever) | The snapshot comes nose-on at ≈ 220–305 px. |
| 5 | IDEAS §5.3 "three … pincer, a fourth frontal" | **At most three attack:** LEAD (frontal) + two flank lanes; a 4th+ is a dry REAR | Research finding 1's three-attacker cap and the density gates. (Plan X9 already recorded this.) |
| 6 | §2.5: REARs spaced by `rear_index / rear_count` | Each REAR has its **own lane**, one `flank_lane_gap` further out per `rear_index`; `rear_count` unused | Measured separation. |
| 7 | §2.5: latch "until the next REPOSITION" | Latched **RUN_IN entry → EXTEND end** (TURN re-derives the next pass) | t9 Revision 3. |
| 8 | §2.5: `flank_stagger` is the one separation fix | Not enough. Added brain-local give-way (slide off a mate's planned track, slow a lead-in, a REAR dry-pass slot) | Round-2 ruled these in the task's discretion. Still brain-local, no shared API. |
| 9 | §2.5 REAR dry passes "every other cycle" | **Open Space only**, a REAR is due on every second window; **in Assault a REAR never dry-passes** (promoted as attackers leave) | An Assault fighter leaves after `passes` passes. |
| 10 | §2.6: SWING_IN reachable from REPOSITION 1.0–1.5 s | REPOSITION lasts the rng 1.0–1.5 s **and** until the new `F` is within `swing_in_reach` (300), capped by `reposition_cap` (5 s); APPROACH hands over on the same rule | Measured: a swing to the other flank is ≈ 891 px (3.4 s at 260 px/s). New config fields `swing_in_reach`, `reposition_cap`, `approach_margin`. |
| 11 | §2.6 Gatling rhythm ≈ 2.8 s (≈ 3.5 shots/s) | Average window period **≈ 5.8 s (≈ 1.7 shots/s)**; the *minimum* is 2.28 s (`min_window_period()`) | Consequence of 10. In Assault at `engage_seconds` 7.0 a Gatling usually gets **one** window, so "attacks from the other side" is rarely seen there. |
| 12 | §2.6.1: "ready" on SPIN_UP entry | "Ready" = stage 1 set when the member's **own spin-up has elapsed** | Entry-based readiness lets the early shooter stream 0.25 s before its partner can, so "both STREAM starts within one tick" could not hold. |
| 13 | §2.6.1: REAR Gatlings "hold at `preferred_range + 200`, never fire" | **Not built.** A third Gatling in a squad fires solo windows | Nothing places three in one squad. Ph14 or a later level edit must decide. |
| 14 | §2.6.1: LEAD opens the window at SWING_IN | Same, and a LEAD **holds in REPOSITION while its own window is open** (`can_start_window()`); only APPROACH / COOLDOWN / REPOSITION FLANKs answer; the FLANK follows the LEAD's *intended* `side` | Review N3. |
| 15 | §2.10 Swarm-shaped idle (only RETURNING deferred) | IDLE and NOTICING are **also** deferred while a burst/window runs | Otherwise a shooter near its anchor goes COMBAT → RETURNING → IDLE in one burst and fires from IDLE. |
| 16 | Config field names (`fire_interval`, `bullet_speed`, `spread_angle`, `bullet_damage` on the Gatling) | Renamed `rail_stream_interval`, `rail_stream_speed`, `rail_spread`, `rail_damage`; the AI stream is `round_speed` 240, `round_damage` 4, `stream_spread` 0.05, `accuracy` 0.8 | So the round-lifetime sweep reads config fields (B5). |
| 17 | §2.9.2: shots/s gate computed (fighter 7 / 1.55, Gatling 12 / 2.8) | **Measured** (`test_level1_fighter_fire_density.gd`): peak shots in any 2 s ÷ 2 ≤ 1.25 × the frozen legacy peak. The analytic figure is printed only | The analytic figure failed (1.86× / 1.90×) with no pre-approved lever able to fix it, while the real run is far quieter (9.0 / 6.5 / 8.5 shots/s). **Owner decision, option A.** The §4 boundary "a 3rd Gatling pushes shots/s over" was dropped as unattainable; replaced by `test_peak_window_rate_rejects_a_dense_burst` and `test_extra_formations_at_the_peak_break_the_count_gates`. |
| 18 | §2.9.3: fighter exit term Razor-shaped (2.84 s) | **Curved-exit bound, 5.37 s**, gated on the real scene (404 starts) | `_tick_disengage` turns the velocity at ≤ 1.35 rad/s, so a fighter flying away from its exit swings round on a ≈ 386 px radius. Worst cloud_descent entry 9.47 s of the 10 s timeout (margin 0.53 s); the real run's container is empty 9.07 s after `waves_complete`. |
| 19 | §2.9.2: levers 1 (engage 6.0 → 4.5) and 2 (`assault_passes`) | **No lever used.** `assault_passes` does not exist; "passes" is the config's `passes` (2) | At 6.0 s an Assault fighter flies exactly **one** lateral pass with one AIMED burst and leaves during EXTEND, so lever 2 would change nothing. |
| 20 | `Steering.lead_target` / `break_contact` | Not built (lead = `TargetInfo.aim_direction()`); `break_contact` stays with the Sniper (Ph4) | Unchanged from the planned decision. |
| 21 | Sprite file renamed with the enemy | `interceptor.png` kept its name (the Gatling's art); **`light_assault_ship.png` is now unreferenced** | Left in place; Ph17 can delete it. |

### Conventions a later phase must keep

(In addition to the "Conventions" list planned above, which all stand.)

- **Fighter pass vocabulary** (`b`, `u = −b`, `l ⟂ u`, `S = P̂ + b·standoff + l`; `left(v) = v.rotated(−PI/2)`) and the
  rule that a lead-in is a `DubinsPath` arriving along the run: reuse it for any later attack-run enemy.
- **A moving player is measured against `P̂`**, the lane's own anchor, never the live player (review N1).
- **A rail shooter is a brain with a fallback, not a silent ship** (the X1 rule above). Ph15 inherits it.
- **A pool is a root child, sized by `pool_size_for` for the AI *and* the rail cadence;** the one named exception is the
  rail Gatling (36, starving by design).
- **Level-1 density gates divide by frozen constants:** `_LEGACY_PEAK_FIGHTERS` 10 / 10 / 8 and `_LEGACY_PEAK_SHOTS_PER_S`
  31.25 / 33.33 / 15.0 (deep_space / planet_approach / cloud_descent). The legacy shooter rate was
  `min(1 / fire_interval, pool / round_lifetime)` (review N6), not a flat 1 / interval.
- **An `ENEMIES_CLEARED` deadline uses the *curved-exit* bound for any enemy that turns its velocity** (Fighter 5.37 s). The
  Ph2 drone rows still use a straight exit.

### Open items — nothing here is decided

- **Owner (from t9, unresolved in the record):** (a) the Assault `engage_seconds` budget — at 6.0 s, 7 of 84 dense Assault
  layouts leave one flank that holds at its start point and leaves without firing, and a longer budget is not
  separation-safe yet (V3 13/42, W5 25/42 over two passes); lever 1 (→ 4.5) would silence most squads. (b) Fighter body
  collision (layer 1, mask 1): squads physically bump. (c) The t9 build took the reviewer's reading, "separation is asserted
  over a full cycle", without a recorded owner answer.
- **Owner (from t17):** `DroneConcurrency.ai_shooter_kinds()` — the t16 *count* gates' fighter lifetime — still uses the
  straight-line exit (9.64 s). With the curved bound (≈ 12.2 s) the reviewer measured deep_space's all-alive peak at **21
  against a limit of 20**; accepting the measured 11.67 s life gives 18. The Ph2 Swarm/Razor deadline formulas also assume
  a straight exit.
- **Wave-order quirk (found, not fixed — triggers are pinned):** `WaveManager` triggers strictly in list order, so in
  deep_space the 2.0 s V5-fighter wave and the 3.0 s drone wave, listed after the 3.5 s gunship wave, trigger at **3.5 s**
  in the game. The analytic gates and the Ph2 drone pin model them at 2.0 / 3.0 s.
- **Gaps in the squad code (measured):** after a death `_reassign()` recomputes every role by distance, which can swap two
  stations and bring two fighters within hull distance (fails up to 9 of 42 W5 layouts, worst 7.3 px); a V6 fails 1 of 42 in
  Open Space; spawn fan-out from 80 px slots overlaps before the first window in 19 of 168 layouts; the shipped level-1
  formations come within 50–54 px of each other against a 57.2 px hull diameter (brief contacts, not gated). `_mates()`
  scans the `enemies` group every tick (fine at V3/W5).
- **The "Assault never fires FORWARD" consequence** of the 6.0 s budget: the close-range Scatter burst and the weapon
  switch are only seen in Open Space (and in a long-budget test). The IDEAS line "in Assault FORWARD is more common" does
  not hold.
- **A moving player in Open Space** (cruising at 200 px/s) gets a breach-shaped pass about every 15 s rather than a clean
  attack run every ≈ 10 s; from abeam or behind, the first pass comes from APPROACH's deadline at 5–11 s.
- **Not play-tested (the gate cannot see it):** whether the passes and the yellow/red lights read at Assault's speed;
  whether level 1's density (fighters now live out their 6 s budget plus a curved exit instead of a rail's on-screen time, but fire about one burst a life) *feels* right; whether
  Open Space's noticing/return feels calm; whether a fighter's in-flight rounds vanishing when it leaves is visible.

### Handed to later phases

| Item | Phase | Note |
|---|---|---|
| Heavy Shell's first consumer | Ph4 (Bomber/Ram) or Ph10 (Heavy Gunship) | Tested with a fixture shooter; no enemy fires it. |
| `EnemyPathMover`'s `"AIStateMachine"` lookup | Ph15 | No subject in the game; pinned on `ai_state_machine_fixture.tscn`. |
| Taking the station's reinforcements off rails; the rail Gatling's pool starvation | Ph15 | Reuses the rail-fallback rule. |
| Owner-bound bullet lifetime (`persist_after_owner_death`), `BulletPool` container injection | Ph5 | In-flight rounds still vanish with their shooter. |
| Cross-squad / cross-family attacker arbitration; richer idle profiles | Ph14 | A fighter squad and a Swarm squad do not know about each other. |
| Leash / re-engage for Open Space fighters | Ph13 | They fight until the player is beyond `lose_radius`. |
| Recolouring legacy enemy bullets; muzzle flash, spin-up particles, enemy SFX; deleting `light_assault_ship.png`; rotating `spawn_offset` with the nose | Ph17 | The `StateLight` is the only telegraph. |
| Rail-Gatling REAR rule, the post-death resync of squad stations | any phase that places three Gatlings / large fighter squads | See open items. |

## Phase 4 - Enemy rework, phase 4: Bomber, Sniper and Ram Corvette (2026-10-07)

Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 1), with research in `1-context.md` and
`2-research.md` in the same directory. These are *planned* decisions. Check this phase's *as built* section, once
written, before relying on them.

### Changes to earlier decisions
- **`persist_after_owner_death` is built in Ph4, not Ph5.** It takes the shape Ph1 designed: a `BulletPool` export,
  default `false`.
  - On `_exit_tree()` with the flag on, every in-flight projectile is **handed over**. The pool's stored recycle
    `Callable` is disconnected, `expired → queue_free` is connected, and the projectile leaves `_active`.
  - `_recycle()` ignores a projectile the pool no longer owns.
  - `cancel_active()` is unchanged whatever the flag says.
  - Ph5 builds owner-distance lifetime and rockets **on** this flag; it does not create its own.
- **Multi-state armour is not a `DefenseProfile` feature.** Armour = breakable parts (`ArmorPlate`) plus a hull rule
  (`is_armored()` / `deflects_hit()` and an `_on_received_damage` deflect). This is the station's
  turret-over-armoured-core pattern.
  - `DefenseProfile.apply_alternate()` stays, with no shipped user. Ph17 may delete it.
  - A mask-based armour is rejected for good: it silently consumes bullets.
- **The armour query is hit-aware, additively.** A target may expose `deflects_hit(hit_box: HitBox) -> bool`. Player
  projectiles call `ArmorQuery.deflects(area, hit_box)` (`global/components/armor_query.gd`), which asks `deflects_hit`
  first and falls back to `is_armored()`.
  - The space station implements neither new method, and its behaviour is unchanged.
  - Any later armoured entity must use one of the two queries. A plate answers "deflect anything that is not ROCKET".
- **Homing rockets steer at `homing_point(from: Vector2) -> Vector2`** when their target has it, else at
  `global_position`. Without it, a rocket deflected by an armoured hull parks at the hull's centre. The station has no
  `homing_point` (a known follow-up for Ph11).
- **Group `ram_ships` and the old Ram's layer immunity are retired.** The Ram Corvette is in `enemies`.
  - The EMP immune list keeps the Ram (renamed `RamCorvette`).
  - The engine-boost immune list drops it: the hull rule protects it while armoured.
- **`TargetInfo.line_of_sight(from, space, exclude := [])`** is real. It delegates to `LineOfSight.clear(space, from, to,
  exclude)` (`global/enemy_ai/line_of_sight.gd`).
- **Heavy Shell:** still no consumer. Ph10 (Heavy Gunship) owns its first use.

### Names and places later phases build on
- **`Steering.break_contact(pos, threat_pos, threat_vel, side, max_speed, lateral_weight := 0.6)`** plus
  `EnemyMover.break_contact(...)`: away from the threat, angled to `side`, with the lateral share doubled while the
  threat is closing.
- **`LineOfSight`:**
  - ray mask `ENVIRONMENT | HAZARD_CONTACT`, bodies only;
  - **opt-in blockers**: group `asteroids`, or a collider answering `blocks_line_of_sight() == true`. Every other body is
    excluded and the ray recast (max 4);
  - physics step only.

  Ph6 wrecks and Ph19 heavy-ship LOS plug in by answering `blocks_line_of_sight()`, not by changing the mask.
- **`ArmorPlate`** (`global/components/armor_plate.gd`) is the first reusable breakable part. Ph10 modular damage
  should extend or compose it, not invent a second one.
  - **Children:** `HurtBox` (512 / mask 96, `accepted_damage_types = [ROCKET]`), `Health`, `Sprite`.
  - **Signals:** `broken(plate: ArmorPlate)`, `deflected(hit_box: HitBox)`.
  - **Methods:** `deflects_hit`, `is_alive`, `set_glow(0..1)`.
  - **Break:** close the hurtbox (deferred), hide, burst, free.
  - **Placement:** parts are never direct children of the enemy root (they sit under a group node such as `Plates` or
    `Turrets`), so the hurtbox-geometry gate's single direct-child `HurtBox` still covers the body.
- **`ContactProfile.Mode.ARMOR`** is appended (value 4). It is armable and armed at `setup()`, never detonates, and
  never harms its owner. The Corvette keeps it armed while plates remain, then uses it RAMMING-style (armed only in
  CHARGE).
- **Enemy ordnance family:** `assault/scenes/projectiles/enemy_ordnance/`. It is separate from the rounds family: not
  `EnemyBullet`s and not `BaseEnemy`s.
  - `EnemyOrdnance extends Area2D` (`Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`), with `expired`, `reset()` and
    `launch()`.
  - A `HurtBox` + `Health` 1, so any player hit **defuses** it (no blast). A proximity area on the player hurtbox. A
    `ProjectileLifetime`. Its own accumulated clock.
  - It detonates through `ContactBlast.spawn`. It is not in `enemies` and never registered with `ScoreTracker`.
  - **Ph7's Mine Layer and mine variants should extend this family.**
- **Rail round:** `enemy_bullet/rounds/rail_round.tscn` (no `WorldEnvironment`), drawn with a self-freeing `RailTrail`
  `Line2D` in the container. `enemy_sniper_bullet.tscn` is deleted.
- **Renames:** `ram_ship/` → `ram_corvette/` (`RamCorvette`, `RamCorvetteConfig`); `sniper_enemy/` → `sniper/`
  (`Sniper`, new `SniperConfig`).
  - `WaveBuilder.ram()`, `sniper()` and the `sniper_enemy()` alias are kept.
  - `Bomber` keeps its name. `bomb.gd/.tscn` are deleted.
- **Sniper telegraph:** the enemy owns `SniperTelegraph`. The player's `SniperAimVisualizer` is not shared with
  enemies any more.

### Conventions
- **A specialist's Assault life is one attack:** sniper `engage_seconds` 9.0 (1–2 shots), ram 4.5 (one charge), bomber
  8.0 (one run).
  - A telegraphed attack is never cut off: the budget defers to the shot, the charge's end or the run's end.
  - An Assault ram exits **straight along its charge heading**. Its deadline row uses a straight-exit bound; the sniper
    and bomber use the measured curved bound (the Ph3 rule).
- **Bombers never spawn in an `ENEMIES_CLEARED` section.** Persisted ordnance would hold it open. This is a deadline
  boundary row, the Gatling precedent.
- **Stationary** means `velocity.length() < 2` px/s and drift < 1 px. A firing point in Assault lies inside
  `inner_rect().grow(−margin)`, where the corridor constraint is identity. The "off-screen band" is the off-camera part
  of `inner_rect()`, never outside it.
- **"Different firing position"** is asserted as a ≥ 45° change of bearing **in the player's frame** (velocity if
  moving, else facing), never as float inequality.
- **Prediction horizons:**
  - the sniper locks on the full rail-speed intercept;
  - the ram uses `clamped_lead_time(…, 0.15, 0.6)`;
  - the bomber uses a damped lead (0.6 × smoothed velocity, horizon ≤ 1.2 s), so a committed turn always escapes.
- **Difficulty hooks:**
  - `SniperConfig.decoy_telegraph` (default `false`) is the first behaviour-branch flag;
  - a decoy is CHARGING-only, never COMMIT;
  - Ph16 should shorten `aim_seconds`, never `lock_seconds` (0.5 s is the reactable floor).
- **Rail fallbacks:**
  - Bomber: a root `_process` clock while suspended, dropping gravity bombs DOWN every 1.2 s.
  - Sniper: `SniperTelegraph`'s own rail cycle at the legacy 2.0 / 0.5 s timings and 1400 px/s, never writing
    rotation.
  - Ram: ARMOR contact.

  `level_2_waves.gd` (unreferenced scene) relies on these.
- **Level-1 specialist density:** `_LEGACY_PEAK_SPECIALISTS` is a frozen per-section constant
  (`test_level1_specialist_spawns.gd`). The gate is ≤ 2.5×. Pre-approved levers: ram engage → 3.5, sniper → 6.0,
  bomber → 6.0. Beyond them it is an owner decision.
- **Hub:** the three specialists take bearings 135° (Sniper), 45° (Bomber) and 225° (Ram) on a ≈ 1700 px ring, drawn
  from the seeded rng **after** the existing four groups. 315° stays free (nearest to the pickup bench).

### Deliberately deferred
| Item | Deferred to | Reason |
|---|---|---|
| Difficulty tiers ("relocates sooner, more varied angles") | Ph16 | Only the decoy flag is in scope; `aim_seconds` / `min_bearing_change` are the levers |
| Sniper marking the player for fighters (squad messages) | Ph14 | |
| LOS blockers in shipped content (wrecks), sniper hiding behind cover | Ph6 / Ph19 | The hub has no physics bodies; the refusal is proven by fixtures |
| Mine variants, minefields, Mine Layer | Ph7 | Ph4's mine is one proximity kind |
| Owner-distance lifetime, enemy rockets | Ph5 | Built on `persist_after_owner_death` |
| Modular damage beyond three plates, per-plate weapons | Ph10 | Builds on `ArmorPlate` |
| Station `homing_point` (rockets parking in the armoured core) | Ph11 | Not changed here, to keep the boss byte-identical |
| `level_2_waves.gd` off rails | Ph15 | Scene unreferenced |
| Deleting `DefenseProfile.apply_alternate()` | Ph17 | No shipped user after Ph4 |
