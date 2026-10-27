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

Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2, after review round 1), with research in `1-context.md` and
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
- **A persistent wall is not an aimed shot.** Ph1's F9 damped lead stays the rule for aimed shots (the gravity bomb and
  the pursuit aim point included). The Bomber's **mine wall** uses an undamped lead on the bomber's own timeline: the time
  its middle mine will be armed (approach left + half the run + arm delay + 0.4 s, capped at 3 s). Ph7's Mine Layer
  should use the same rule for any wall it lays.
- **Budgets count from spawn, so attacks must be proven to fit.** Every Ph4 specialist has an **attack-in-budget row**:
  from each level-1 spawn class, through a real `WaveManager`, it reaches its attack state (Ram WIND_UP, Sniper AIM,
  Bomber RUN) before its Assault budget expires. Every density or deadline lever is legal only while those rows stay
  green. Later phases should add the same row for any enemy with a budget.

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
  - **Children:** `HurtBox` (512 / mask 96, `accepted_damage_types` empty), `Health`, `Sprite`.
  - **One hit-aware classifier** on the HurtBox's `area_entered` (never `received_damage`, which carries no type):
    `breaks_on(hit_box)` = `ROCKET`, or the projectile answers `is_high_impact() == true`. Breaking hits decrease Health;
    others emit `deflected`. Direct emitters (beam, nova, dash) do nothing to a plate.
  - `deflects_hit(hit_box)` = `not is_alive() or not breaks_on(hit_box)`: a plate broken this frame consumes nothing.
  - **Signals:** `broken(plate: ArmorPlate)`, `deflected(hit_box: HitBox)`.
  - **Methods:** `deflects_hit`, `is_alive`, `set_glow(0..1)`.
  - **Break:** close the hurtbox (deferred), hide, burst, free.
  - **Placement:** parts are never direct children of the enemy root (they sit under a group node such as `Plates` or
    `Turrets`), so the hurtbox-geometry gate's single direct-child `HurtBox` still covers the body.
- **`ContactProfile.Mode.ARMOR`** is appended (value 4). It is armable and armed at `setup()`, never detonates, and
  never harms its owner. The Corvette keeps it armed while plates remain, then uses it RAMMING-style (armed only in
  CHARGE).
  - `shove_speed` (default 0): an armed touch calls the touched owner's duck-typed `apply_knockback(impulse)` (IDEAS §16
    "stagger"). The Corvette shoves at 260 px/s while armoured only.
  - **`OpenSpacePlayerShip.apply_knockback(impulse)`** exists from Ph4: `velocity += impulse`. Never call
    `PlayerBase.apply_knockback_motion()` in Open Space: it clamps to the Assault bounds.
- **`Bullet.is_high_impact()`** returns `unlimited_pierce` (the player's Sniper Shot). It is the duck-typed opt-in for
  "high-impact weapons" (IDEAS §5.7); a later heavy player weapon answers it to break armour parts.
- **Enemy ordnance family:** `assault/scenes/projectiles/enemy_ordnance/`. It is separate from the rounds family: not
  `EnemyBullet`s and not `BaseEnemy`s.
  - `EnemyOrdnance extends Area2D` (`Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`), with `expired`, `reset()` and
    `launch()`.
  - A `HurtBox` + `Health` 1, so any player hit **defuses** it (no blast). A proximity area on the player hurtbox. A
    `ProjectileLifetime`. Its own accumulated clock.
  - It detonates through `ContactBlast.spawn`. It is not in `enemies` and never registered with `ScoreTracker`.
  - Lifetime caps: gravity bomb 16 s / 1800 px, pursuit bomb 10 s / 2400 px, mine 10 s (life 8 s).
  - **Ordnance has per-kind rows in `test_enemy_bullet_lifetime.gd`** (constant speed; a two-speed travel bound for the
    pursuit bomb; time-only for mines), speeds read from config. **Ordnance speeds never enter
    `_every_shipped_enemy_bullet_speed()`**, which stays the round family's list (its ≥ 150 px/s rule and derived
    18 s / 2400 px defaults are round-only).
  - **Ph7's Mine Layer and mine variants should extend this family.**
- **Rail round:** `enemy_bullet/rounds/rail_round.tscn` (no `WorldEnvironment`), drawn with a self-freeing `RailTrail`
  `Line2D` in the container. `enemy_sniper_bullet.tscn` is deleted.
- **Renames:** `ram_ship/` → `ram_corvette/` (`RamCorvette`, `RamCorvetteConfig`); `sniper_enemy/` → `sniper/`
  (`Sniper`, new `SniperConfig`).
  - `WaveBuilder.ram()`, `sniper()` and the `sniper_enemy()` alias are kept.
  - `Bomber` keeps its name. `bomb.gd/.tscn` are deleted.
  - Art: `bomber.png` and `sniper.png` are overwritten in place (UIDs kept); `ram_corvette.png`, two plate PNGs and
    `sniper_barrel.png` are new; `ram_ship.png` / `ram_ship_damaged.png` are deleted in the ram art task.
  - The Bomber's body is a `RectangleShape2D` (≈ 96 × 44) shared by its contact box and hurtbox, so a wide sprite is
    shootable where it is drawn.
- **Sniper telegraph:** the enemy owns `SniperTelegraph`. The player's `SniperAimVisualizer` is not shared with
  enemies any more.

### Conventions
- **A specialist's Assault life is one attack:** sniper `engage_seconds` 9.0 (1–2 shots), ram 4.5 (one charge), bomber
  8.0 (one run), each proven by its attack-in-budget row.
  - Speeds sized for that: ram `cruise_speed` 280 (exposed 340), Bomber transit 240 and run 170; the sniper's first
    firing point is the nearest legal one.
  - A telegraphed attack is never cut off: the budget defers to the shot (≤ `aim + lock` 1.8 s), the charge's end
    (≤ `wind_up_seconds + charge_max_time` = 0.65 + 1.45 = 2.1 s) or the run's end (≤ 2.12 s).
  - **The Ram's LINE_UP never defers.** It is capped at `line_up_cap` (0.5 s) and entered only if
    `budget.remaining() ≥ line_up_cap` (the Swarm Drone / Gatling attack-gate precedent). `charge_max_time` is a hard
    cap on the charge boost.
  - An Assault ram exits **straight along its charge heading** after a charge. Its deadline row uses the larger of the
    straight bound and the measured nearest-edge bound; the sniper and bomber use the measured curved bound (the Ph3
    rule). **Count gates use measured exits too**, never a straight-line exit for a curved exiter.
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
  - the bomber's gravity bomb and pursuit aim use a damped lead (0.6 × smoothed velocity, horizon ≤ 1.2 s);
  - the bomber's mine wall uses the undamped bomber-timeline lead above, only for 150 ≤ |v̄| ≤ 440 px/s (a boosting
    player gets a pursuit bomb). Its placement test asserts against the **live** player, not only against P̂.
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
  (`test_level1_specialist_spawns.gd`). The gate is ≤ 2.5×, in all three sections (cloud_descent included). Pre-approved
  levers, in order, each conditional on the attack-in-budget rows: ram `exit_speed` → 600, sniper engage → 7.0, bomber
  → 6.5, ram engage down to its measured floor. Beyond them it is an owner decision.
- **Hub radii (perceive / lose):** Sniper 700 / 1300, Bomber 650 / 1700, Ram 600 / 1300. Each `lose_radius` sits above
  the largest actor–player distance the enemy's own cycle opens, by a config inequality. Ph3's 900 is a fighter value;
  a later specialist must size its own the same way, or `AnchorIdle` sends it home mid-cycle.
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
| Reconciling the race-mode mine (`assault/scenes/race/track/mine.gd`, group `mines`) with enemy ordnance mines | Ph7 | Two unrelated mine concepts exist; Ph4 does not touch the race one |
| Player knockback from anything other than armour contact | later (Ph6 hazards, Ph17) | Ph4 adds only the Open Space ship's `apply_knockback` the shove needs |
| A warhead-friendly Assault ram (`assault_plate_count` 1) | owner decision | A frontal warhead volley strips one plate; one homing volley strips all three. Default keeps three plates |
| `level_2_waves.gd` off rails | Ph15 | Scene unreferenced |
| Deleting `DefenseProfile.apply_alternate()` | Ph17 | No shipped user after Ph4 |

### Phase 4, built in t4 (armour query, `ArmorPlate`) (2026-10-08)
- `ArmorPlate` resolves each `HitBox` through one **idempotent** `_resolve(hit_box)` (decision recorded per HitBox instance id, erased on the hurtbox's `area_exited`), called from both its own hurtbox `area_entered` and `deflects_hit()`. Revision 2 of the plan had the plate damage itself in `area_entered` and answer `deflects_hit()` from live state, which made "the rocket that breaks a plate is consumed" depend on Godot's undefined callback order (review round 2, B2). Later phases adding breakable parts (Ph10) keep this shape.
- The plate builds its `HurtBox` / `Health` / `Sprite` in `_ready()` when the scene does not author them (exports `max_health` 50, `hurt_size`, `texture`). A plate's HurtBox is the area the projectile overlaps, so `ArmorQuery` reaches `ArmorPlate.deflects_hit` directly (`area.get_parent()` is the plate); the entity root's `is_armored()` only answers for the hull.
- The Sniper Shot is not routed through `ArmorQuery` (`bullet.gd`'s `unlimited_pierce` branch returns before it); it damages the plate only through the plate's own classifier. The Sniper Shot's scene damage is 50, so a plate (HP 50) falls to one unmodified shot; the t4 test sets 40 to prove the two-shot rule. The weapon-mode damage decides the real figure.

### Phase 4, built in t6 (enemy ordnance) (2026-10-08)
- `EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/`) is one script, `Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`, with `launch(dir, speed, target_point)`, `reset()`, `signal expired`, and the accessors `heading()`, `is_armed()`, `is_warning()`. The dropper sets `blast_radius`, `blast_damage`, `trigger_radius`, `arm_delay`, `warning_time` (and `mine_life`, the pursuit exports) BEFORE `launch()`; `EnemyOrdnanceScenes.scene_for(kind)` / `pool_size_for(kind, cfg)` (duck-typed on `max_mines_per_run`, `mine_life`, `min_run_period`).
- The trigger is a **poll** of `ProximityArea.get_overlapping_areas()` each tick once armed (not `area_entered`), and arming counts from `launch()`: a player already inside the radius at arm time still sets it off (plan review round 2, B1b). B1 (a)/(c)-(e) - the mine wall's warning versus player speed, the wall timing margin and the live-player outcome test - are **t10's**; the mine scene ships the plan's 0.5 s warning and t10 must set `mine_warning` so `(trigger_radius + blast_radius) / mine_warning >= mine_speed_max`, or make an armed mine detonate on entry.
- A pursuit bomb accelerates from its launch speed to `final_speed` at `accel` (600 px/s^2) after the steer window instead of jumping, so the plan's 7.46 s lifetime bound is slightly optimistic (about +0.2 s; still far inside 10 s).
- The ordnance rows in `test_enemy_bullet_lifetime.gd` and `test_enemy_ordnance.gd` read their speeds from `tests/helpers/ordnance_config_fixture.gd` (the field names `BomberConfig` will carry). **t9 must give `BomberConfig` those fields and point both tests at it, then delete the fixture.** `bomb.gd` / `bomb.tscn` are untouched (t9 deletes them).

### Phase 4, built in t9 (Bomber shell) (2026-10-08)
- `BomberConfig` is flat and carries every §2.4 field plus the ordnance fields (`gravity_*`, `mine_*`, `pursuit_*`, `trigger_radius`, `min_run_period`, `max_mines_per_run`) the lifetime rows and `test_enemy_ordnance.gd` now read from the shipped `bomber_config.tres`; `tests/helpers/ordnance_config_fixture.gd` is deleted, and `bomb.gd` / `bomb.tscn` with it. The old `movement_speed` / `bomb_interval` fields are gone (`rail_bomb_interval` replaces the latter). The mover's turn-cap field is named `max_turn_rate` (not `turn_rate`).
- **`mine_warning` ships at 0.25 s, not the plan's 0.5 s** (review round 2, B1a). `test_bomber.gd` asserts `(trigger_radius + mine_blast_radius) / mine_warning >= mine_speed_max` (128 / 0.25 = 512 >= 440), so a player crossing a mine at the top of the mine band is still inside the blast when it fires. B1 (c)-(e) (the wall-margin measurement and the live-player outcome test) remain t10's.
- New field `rail_bomb_range` (600 px, the legacy 5 s fuse at 120 px/s): the aim point of a rail gravity bomb, which sets its `max_travel`.
- `Bomber.drop(kind, dir, speed, target_point)` is the one place ordnance is taken from a pool and configured; t10's brain calls it. The three pools are root children with `persist_after_owner_death = true`, sized in the scene (4 / 10 / 4) and gated against `pool_size_for` in `test_bomber.gd`.
- `BomberBrain.Phase` is `{ APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE }`; t19 appends IDLE / NOTICING / RETURNING. In t9 the AI Bomber only intercepts in APPROACH (no hub idle, no drops); budget expiry goes straight to DISENGAGE (t10 adds the RUN deferral).

### Phase 4, built in t10 (Bomber bombing runs) (2026-10-11)
Task plan: `docs/plans/cmuyk2qpr0089oa2xlih7xvmg/3-plan.md` (Revision 3, review round 3 APPROVED; "As built" at its end).
- **Mine-wall lead (B1c):** `c = (run_length / 2) / run_speed + mine_arm_delay + wall_margin + (trigger_radius + arc_depth) / |v|`, `t_wall = t_approach_left + min(c, mine_horizon)`, undamped. Only `c` is capped, so the lead-in is planned to where the wall will be on ARRIVAL and a constant-velocity player's wall stands still during APPROACH (measured: 1.5 px over the last 1.0 s). Gravity / pursuit keep the damped lead (`lead_factor` 0.6, `horizon` 1.2). `mine_horizon` stays 3.0 (c <= 2.69 s at 150 px/s).
- **Arrival time, as built:** NOT the Fighter's 3x fixed-point iteration (it diverged from a standing start: a far goal makes a loop, which makes a later goal). The brain scans T in 0.1 s steps up to `approach_cap` for the earliest T whose lead-in can be flown in time, then bisects (5x); flight time includes accelerating from the current speed at `acceleration`. The tracked Dubins path is only replaced when its goal moved > 24 px or the bomber is > 40 px off it (the Fighter's numbers).
- **Line capture, new:** within 96 px / 45 deg of the line, from 160 px before its start to its middle, the bomber pursues a point 80 px ahead on the line instead of a fresh curve, and the time left reads NEGATIVE once it is past the start (`-s / run_speed`). Without it a re-plan near the line produced a loop, and at 440 px/s a 0 there let the wall slide ahead at the player's speed. RUN entry stays lateral <= 32 px, heading <= 12 deg, run coordinate in [-32, L/2].
- **Angled line (GRAVITY / PURSUIT), deviation:** the side is the one with the SHORTER lead-in (the plan's "toward the heading" rule, then corridor centre, then rng, only breaks a tie), and the angle narrows from `approach_angle` 35 deg to 0 in four steps to the widest one whose lead-in has no loop (shorter than pi x plan radius). With the line's start `L / 2 + gravity_release_lead` (300 px) from P-hat, any bomber closer than about 880 px sits BESIDE the start at 35 deg and could only reach it by looping (~6.4 s at the 244 px plan radius, past `approach_cap`), so a close GRAVITY run was unflyable as planned. Close in the pass is near-direct; from range it is the full angle. A bomber already inside the RUN entry window counts as a zero-length lead-in. Chosen once per APPROACH (`approach_angle_used` exposes it).
- **PURSUIT line** passes BESIDE P-hat: P-hat abeam the line's end at the new `pursuit_launch_range` (300 px), the bomb launched at the midpoint (task-plan F2). **GRAVITY** overflies P-hat and releases when the live damped P-hat is <= `gravity_release_lead` ahead, now **120 px (was 80)**, asserted `>= trigger_radius + gravity_bomb_speed * gravity_bomb_arm_delay` (R2-2); the bomb inherits the heading.
- **Mines by distance:** `n` in [3, 5] rest points 70 px apart around `s* = (P - start) . dir`, bowed up to `arc_depth` toward the player's side; each released `mine_eject_speed * mine_eject_time / 2` (24 px) past its rest coordinate and ejected at `2 |rest - pos| / mine_eject_time`, so it stops on its point (measured within 4 px). New config field `mine_eject_time` (0.3), applied to the mine by `Bomber.drop()`. Whatever a run did not get to drop goes at its end, so a run always delivers its whole pattern.
- **RUN stall guard:** `line_length / run_speed + 0.25 s` (<= 2.37 s) — the Assault deferral bound when the budget expires mid-run. Assault: one run per life — RUN -> ESCAPE -> DISENGAGE, or RUN -> DISENGAGE if the budget expired during it.
- **Rejected R4.5 example (B1e), recorded not honoured:** a boosting player (> `mine_speed_max` 440) gets a pursuit bomb, never a mine chain; a wall for a boosting player needs a lead longer than `mine_horizon`. Owner question for the difficulty phase (16). R2-5: a player boosting steadily is reached only head-on — a boost is temporary.
- **Seams:** `ordnance_kind`, `line_start` / `line_dir` / `line_length`, `planned_rest_points`, `drops_this_run`, `runs_started`, `smoothed_velocity()`, `predicted_drop_point()`, `line_centre()`, `wall_clamped()`, `wall_lead_at_entry(speed)`, `damped_aim_point(p, v, from)`, `choose_kind(speed, d)`.
- **Measured (REPORT):** head-on 220 px/s wall: middle mine 131.8 px ahead of the live player when it arms (> 80); a straight 220 px/s stub takes a blast, the same stub turning 90 deg at RUN entry takes none (both modes); 440 px/s takes a blast (Open Space). Attack-in-budget from (0, -400): RUN at 1.57 / 2.33 s (stationary stub at centre / +200 px) and 4.42 / 4.73 s (moving 220 px/s), of 8.0; one run per life. The Revision 2 numbers (no B1c term) fail the "> trigger_radius ahead" row at 42.9 px; the Revision 1 lead (damped 0.6, frozen at APPROACH start) lays no wall at all from the head-on set-up (no RUN in Open Space; Assault cycles to a gravity run).
- **Gate time budget (found in attempt 6):** the harness kills verification at about 300 s (attempts 2-5 each ended exactly 5:00 after the session; passing tasks took 4.4-4.7 min). At 1x the t10 real-physics rows cost 67 s and took the gate to 348 s. They, and the whole of `test_enemy_ordnance.gd` (53 s), now run 8x faster with the step kept at 1/60 game-second (`Engine.time_scale`, `physics_ticks_per_second` and `max_physics_steps_per_frame` scaled together, restored in `after_each`; the pattern `test_level1_fighter_fire_density.gd` set). Gate now ~244 s. Every outcome is unchanged except the +200 px stationary row (RUN 2.25 -> 2.33 s, the spawn frame). **Later tasks: a test that awaits real physics frames costs wall clock against that cap; scale the clock.** The two biggest remaining files are `test_fighter_squad.gd` (65 s, 1x) and `test_level1_fighter_fire_density.gd` (61 s, already 4x).

### Phase 4, built in t12 (Sniper shell) (2026-10-11)
- `SniperConfig` is flat and carries every §2.5 field (movement, firing-point, shot, engagement, decoy, rail) plus **`rail_fallback_damage` (25)**, which the plan did not list: the rail fallback fires today's 1400 px/s shot at today's damage (the AI round's `rail_damage` is 28). HP 60 / contact 20 / score 50 are the legacy values; `Sniper` no longer hardcodes its score.
- `rail_round.tscn` is `EnemyRounds.RAIL` (inherited `enemy_bullet.tscn`, speed 2200, `Visual` core + `Glow`, capsule r 1.5 × h 24, 4 s / 2400 px, no `WorldEnvironment`). `enemy_sniper_bullet.tscn` is deleted; `test_enemy_bullet_lifetime.gd` reads `rail_speed` / `rail_fallback_speed` from the config and its unpooled-shot case became a pooled one (the round is recycled, not freed, on crossing the legacy rect).
- `SniperTelegraph` (node `Telegraph`) owns the aim line (`show_line(aim_point, locked)` / `hide_line()` / `line_points()`) and the rail cycle (`start_rail_cycle()`, started by `SniperBrain.on_suspended()`). t13/t14 drive the same `show_line()` for the AI cycle and the decoy. The cycle keeps its own aim direction and never writes `rotation`.
- `SniperBrain.Phase` is `{ ENTER, BREAK_CONTACT, RELOCATE, SETTLE, DECOY, AIM, LOCK, FIRE, DISENGAGE }`; t12 plays only ENTER and DISENGAGE. ENTER's arrival **latches with hysteresis** (arrived within `arrive_radius`, re-seek beyond twice it): `Steering.arrive` at rest has a zero slowing radius and otherwise chatters at full speed round the point. t13's SETTLE should reuse that shape. `nearest_firing_point(player_pos)` is the t12 stand-in for `choose_firing_point()`.
- The art is nose-up, so `Sniper.sprite_forward_angle = -PI / 2` (the muzzle stays at local (0, -20)); the old `rotation = PI` override is gone. The `Barrel` is a `GradientTexture2D` placeholder (no PNG) until t15.
- The `shot_count` export / `.prop("shot_count", N)` is gone; the rail shot count is `SniperConfig.rail_shot_count`. On a rail the cycle now starts at `suspend_ai()`, not after a 2.5 s fly-in, so a rail sniper fires its first round about 2.5 s after spawn; t21 owns re-timing level 1.

### Phase 4, built in t13 (Sniper cycle) (2026-10-11)
Task plan `docs/plans/cmuyk2qq0008loa2xqwco8raj/3-plan.md` (Revision 2, review APPROVED in round 2).
- **ENTER → SETTLE**, not ENTER → BREAK_CONTACT as the epic's §2.5 diagram draws it: ENTER is the seek to the first (nearest legal) firing point, so there is nothing to break from yet. `nearest_firing_point()` stays as ENTER's fallback when `choose_firing_point()` finds nothing legal.
- **`break_min` (1.0 s)**: BREAK_CONTACT never ends sooner, because after FIRE the sniper is already at its range and "until `0.9 · range`" would end it on its first tick (breaking the §4 post-shot row). `_break_time` counts from entry and is never reset; past `range + range_jitter` it requests zero (waits) instead of flying off; after a choice finds nothing it retries only every `break_cap`.
- **Firing-point tiers A/B/C**: A = Δ ≥ `min_bearing_change` + 5° (`BEARING_SLACK`), B = Δ ≥ 45°, C = the logged fallback. A exists because the bearing that counts is the one the sniper actually fires from (latch + overshoot ≈ 2°).
- **New filter, path clearance** (`pass_clearance_ratio` 0.45 × range, or no closer than the sniper already is): with the epic's weights the separation term always wins, so the best candidate was the far side of the player and a straight RELOCATE flew through it (review round 1, finding 1). 0.45 rather than 0.6 so an Assault sniper can still cross over the top of a player near the bottom of the corridor (the ±60° chord passes at 340 px).
- **RELOCATE's re-pick deadline is per trip**, `max(relocate_cap, trip / relocate_speed + 1 s)`: the flat 4 s cap re-picked most Open Space relocations (1500–1800 px) mid-route. A reach filter (`travel ≤ relocate_speed · relocate_cap`) was tried and rejected: with the coarse seeds it left no ≥ 45° candidate at the 900 px Open Space range. Known gap (review round 2, N2): the later re-pick means a sniper can aim from a point a boosting player has left far behind; nothing checks the range before AIM.
- **LOCK re-checks line of sight on two lines**: muzzle → player and muzzle → lock point. SETTLE checks muzzle → player. Every refusal is counted in `SniperBrain.refusals`.
- **Assault BREAK_CONTACT is corridor-safe**: an outward request on an axis is zeroed within `break_speed² / (2 · 0.5 · acceleration) + 16 px` of the visible rect's edge; a remainder toward the player is turned round (that slide may cross the player's line — the corridor wins); a corner stops it.
- **`RailTrail`** (`assault/scenes/projectiles/enemy_bullet/rounds/rail_trail.gd`, code-built `Line2D`, `spawn(round, origin, fade)`, `step(delta)`, `following`, `global_points()`) is added to the round's container. Phase 13 / t22 note (review round 2, N4): it is a child of the `EnemyContainer`, which `LevelDirector._wait_enemies_cleared` counts, so a trail can hold an ENEMIES_CLEARED section open up to `trail_fade` (0.4 s) after the last sniper leaves.
- New flat `SniperConfig` fields: `break_min`, `velocity_smoothing`, `frame_speed`, `forward_cone_speed`, `seed_jitter`, `random_candidates`, `max_los_rays`, `pass_clearance_ratio`, `barrel_unfold_seconds`, `barrel_fold_seconds`. `SniperBrain` gains `muzzle`, `pool`, `barrel` (wired by `sniper.gd`), `choose_firing_point()`, `player_frame()`, `bearing_of()`, `target_point`, `shots_fired`, `refusals`, `last_bearing`/`has_last_bearing`, `lock_point`/`lock_origin`, `last_round`/`last_trail`, `barrel_open`, `disengage_pending`, and the test record `last_candidates` / `last_choice_fallback` / `last_los_rays`. The barrel's fold is a `scale.y` / `position.y` pose on the placeholder sprite; t15 swaps the art.

### Phase 4, built in t14 (Sniper decoy) (2026-10-12)
- **`SniperBrain.Phase.DECOY`** is live behind `SniperConfig.decoy_telegraph` (default false; the shipped game never enters it). SETTLE → DECOY → AIM when on; SETTLE → AIM when off, unchanged. Ph16 maps a difficulty tier onto the flag.
- The decoy line is `SniperTelegraph.show_decoy_line(point)` (`DECOY_COLOR` dim orange, `DECOY_WIDTH` 1): the muzzle→player direction rotated by `brain.decoy_angle`, a signed offset drawn uniformly in `decoy_offset_min..max` (25–35°), side by coin flip per decoy. It re-derives from the player's current bearing every tick, so the offset never shrinks. StateLight CHARGING (never COMMIT); no round is acquired. The sniper keeps **facing the player** during DECOY (the barrel is a placeholder, and turning to the fake would move the muzzle off the measured bearing). The barrel unfolds in DECOY as it does in AIM.
- A budget expiry in DECOY disengages at once (a fake aim is not a shot to finish, unlike AIM / LOCK). The decoy adds `decoy_seconds` (0.6 s) to the cycle only when the flag is on, so the level-1 attack-in-budget rows (flag off) are unaffected.

### Phase 4, built in t16 (Ram Corvette armour) (2026-10-12)
Task plan `docs/plans/cmuyk2qq8008xoa2xxoq1frgn/3-plan.md` (Revision 2).
- **Exposure is deferred** (`call_deferred("_expose")`) to the end of the physics step the last plate breaks in: `HurtBox.received_damage` carries no hit, so a rocket that breaks the last plate while overlapping the hull would otherwise also land on the hull. `is_armored()` reads true for the rest of that step; `armor_broken` fires once, one step after the last `plate_broken`. t17's glow / stagger / disarm should hang off `armor_broken`, not the third `plate_broken`.
- Scene: body `CircleShape2D` r 34 shared by the body, the root `HurtBox` (default `DefenseProfile`, mask 1121; no profile authored) and `ContactHitBox` (**mask 128**, not 0: `ContactProfile` reaches `contact_made` and the ARMOR shove only through the hitbox's own `area_entered`). Plates: `Plates/PlateFront` (0, 36), `PlateLeft` (35.45, −6.25) at −100°, `PlateRight` mirrored; "left" is the ship's left (nose = local +y, so left = local +x). Capsules r 6, height 36 (front) / 28 (sides), tangential; the side plates' inner edge (~27–28 px) clears a frontal warhead volley's 23 px reach. Placeholder art: `Sprite2D` `ram_ship.png` (`rotation = PI`, scale 2.6) and a `Polygon2D` under each plate's `Sprite` — t18 swaps both.
- `RamCorvetteConfig` is flat: `max_health` 120, `collision_damage` 50, `score_value` 35, `plate_health` 50, `exposed_collision_damage` 60, `armor_shove_speed` 260, `cruise_speed` 280, `acceleration` 500, `max_turn_rate` 2.2, `engage_seconds` 4.5, `exit_speed` 500. **`movement_speed` is removed** (nothing reads it). t17 appends the charge fields.
- `RamCorvetteBrain.Phase` is `{ APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE }` (values fixed; hub phases appended later); t16 plays only APPROACH (plain intercept, `INTERCEPT_LOOKAHEAD` 0.5) and DISENGAGE (the Bomber's exit). `phase_changed(new_phase: int)`, `enter_phase()` seam.
- `RamCorvette` gains `is_armored()`, `deflects_hit()`, `is_laser_blocking()`, `homing_point(from)`, `live_plate_count()`, signals `armor_deflected(damage: int)`, `plate_broken(plate_name: StringName)`, `armor_broken`; joins `enemies`; the `ram_ships` group, `_enter_damaged_state()`, `ram_ship_damaged.png`'s load and its `apply_alternate()` use are gone. The ARMOR profile stays armed after exposure (the disarm-outside-CHARGE rule is t17).
- Outside: `bullet.gd` drops the `ram_ships` stop (X4); `EngineBoostModule._IMMUNE_CLASSES` drops `RamCorvette` (EMP keeps it); `DefenseProfile.apply_alternate()` has no shipped user (kept, tested on `fixture_enemy.tscn`).

### Phase 4, built in t17 (Ram Corvette charge) (2026-10-12)
Task plan `docs/plans/cmuyk2qqb0091oa2xy7yn9sxa/3-plan.md` (Revision 2, review round 2 APPROVED).
- **`RamCorvetteBrain.Phase` gains `STAGGER`, appended after DISENGAGE** (value 6; t16's values unchanged). t19 appends IDLE / NOTICING / RETURNING after it. A plate broken in LINE_UP / WIND_UP enters it (0.4 s, then LINE_UP through the gate, APPROACH, or DISENGAGE if the budget expired meanwhile); a plate broken in CHARGE or STAGGER changes nothing.
- **Attack gate is `remaining() >= line_up_cap + ATTACK_GATE_MARGIN` (0.05 s)**, not bare `>= line_up_cap`: the budget is updated before the phase logic, so without a few ticks of margin a LINE_UP started at exactly 0.5 s left could expire on its last tick. Still satisfies "LINE_UP only if remaining() ≥ line_up_cap". t21 lever 4's ram floor is therefore worst spawn-to-LINE_UP + 0.55 s.
- **Assault APPROACH = the intercept point (0.5 s ahead) + `(side, vside) * assault_side_offset`**, sought at cruise; with the offset at 0 it is exactly Open Space's intercept (`test_enemy_dual_mode.gd`'s identity case zeroes it). Side tie-break for centred rams (epic review N5): the side it is on (≥ 8 px), else the roomier corridor half, else a seeded `rng` coin; flipped if that point would sit within 64 px of the corridor edge and the other would not. Measured on every level-1 offset: 28–43° off vertical.
- **New `RamCorvetteConfig` field `braking` (1600 px/s²)**, written to the mover only on entry to LINE_UP / WIND_UP / STAGGER (0 = the mover's `acceleration` elsewhere), so WIND_UP is ≤ 30 px/s even straight out of a 700 px/s charge ((700 − 30) / 1600 = 0.42 s < `line_up_cap`) without tightening the post-charge slow-down or the wide turn. Other new flat fields: `engage_range` 420, `assault_side_offset` 240, `line_up_cap` 0.5, `line_up_tolerance_deg` 8, `lead_min` 0.15, `lead_max` 0.6, `crawl_speed` 20, `wind_up_seconds` 0.65, `windup_track_fraction` 0.6, `windup_track_rate` 0.8, `charge_speed` 620, `overshoot` 220, `charge_max_time` 1.45, `wide_turn_rate` 1.4, `wide_turn_exit_angle_deg` 30, `glow_fade_seconds` 0.3, `stagger_seconds` 0.4, `exposed_cruise_speed` 340, `exposed_charge_speed` 700, `evade_cone_deg` 20, `evade_range` 600, `evade_speed` 180.
- **WIDE_TURN ends → LINE_UP only when in `engage_range` and the gate is open, else APPROACH** (the epic says LINE_UP; a charge can end ~900 px out). It also ends after `WIDE_TURN_CAP` 4 s (a player circling inside the turn could hold it forever).
- **Glow:** one fade rule (1 / `glow_fade_seconds` per second) through WIDE_TURN, APPROACH and LINE_UP; WIND_UP ramps from whatever is left to 1 (never snaps); STAGGER and DISENGAGE zero it. `RamCorvette.set_plate_glow(amount)` drives every live plate's `ArmorPlate.set_glow` - t18's plate art hangs off that.
- **Rails:** `on_suspended()` latches `suspended`; `on_exposed()` / `on_plate_broken()` then do nothing, so a railed ram's ARMOR contact stays armed for life after its plates go (60, no shove, from `_expose`). Matters until t21/t22 take level 1's rams off rails.
- `RamCorvetteBrain` public state for tests and later tasks: `exposed`, `suspended`, `disengage_pending`, `side`, `vertical_side`, `aim_point`, `aim_dir`, `aim_frozen`, `charge_dir`, `charge_point`, `charge_origin`, `charge_duration`, `charge_started_at`, `charges`, `first_wind_up_at`, `turn_dir`, `glow`, `evade_nudge`, `contact` (wired by `ram_corvette.gd`), `can_attack()`, `cruise_speed()`, `charge_speed()`, `on_plate_broken()`, `on_exposed()`.
- Attack-in-budget (§2.9.4), every level-1 ram offset, one per run: WIND_UP at 2.08–2.35 s (stub at camera centre) and 2.80–3.07 s (stub 200 px away), 1.43–2.42 s of budget left, one charge per life. Cruise 160 on the top-wide class never winds up.

### Phase 4, built in t18 (Ram Corvette art) (2026-10-12)
- New art: `ram_corvette.png` (84 x 84, nose-down, no plates painted on), `ram_plate_front.png` (44 x 18) and `ram_plate_side.png` (36 x 18, +x end chamfered); each is a 40 x 14 / 32 x 14 slab inside 2 px of transparent margin (the 90% opacity gate needs a margin or a notched edge on a plate this small). The hull is a PixelLab `create_map_object` pick (`high top-down`, 1 of 7 candidates); the two plates are drawn by script, as the generated slab came with a painted-on orange glow strip that would have fought `set_plate_glow()`'s tint.
- Scene: only textures swapped. The hull `Sprite2D` loses its `rotation = PI` / scale 2.6 (the new art is native size and nose-down); each plate `Sprite` takes its texture and the `Polygon2D` placeholders are gone. `PlateLeft`'s sprite sets `flip_h` (the mirrored side plate). Texture refs are UID-less (legal; a `.import` is minted on import).
- The old Ram Ship hull and damaged-hull PNGs and their `.import` files are deleted. Highest non-station opaque fraction is now `assault.png` 58.03%; `ram_corvette.png` is 55.21%.

### Phase 4, built in t19 (specialist hub idle) (2026-10-14)
- `SniperBrain`, `BomberBrain` and `RamCorvetteBrain` get the Fighter's hub idle: `Phase` appends `IDLE`, `NOTICING`, `RETURNING` (sniper 9-11, bomber 5-7, ram 7-9), plus `patrol_anchor`, `anchor_idle`, `idle_phase_offset` and the **`start_engaged` test seam** (set it before the first tick to skip the idle). Assault builds no `AnchorIdle` and starts in combat, as before. Every existing test that spawns one of the three in the Open Space harness now sets `start_engaged = true` (marked `# pre-t19`).
- Each config gains an `Idle` group: `perceive_radius`, `lose_radius`, `notice_time` 0.35, `idle_radius` 150, `idle_speed` 0.5. Radii: Sniper 700 / 1300, Bomber 650 / 1700, Ram 600 / 1300, written to the `.tres` files too. The §2.10 inequalities are asserted from those fields in each enemy's test file.
- **What RETURNING may not interrupt:** the sniper's DECOY / AIM / LOCK / FIRE, the bomber's RUN, the ram's WIND_UP / CHARGE. Anything else (APPROACH, ESCAPE, REPOSITION, LINE_UP, WIDE_TURN, BREAK_CONTACT, RELOCATE, SETTLE) goes home at once. The return is retried every tick, not queued.
- **Quirk worth knowing for the hub (t20):** `AnchorIdle` keeps its own state while a protected phase runs. A ram whose charge carried it to within `idle_radius` of its anchor reaches the AnchorIdle `IDLE` state during the charge, and then enters `IDLE` directly, with no `RETURNING` phase; the ring orbit brings it home. Same for the Fighter. No change to `AnchorIdle`.
- Idle speed per enemy: sniper `relocate_speed`, bomber `max_speed`, ram `cruise_speed` (the `max_correct_speed` of `Steering.orbit` / `arrive`).

### Phase 4, built in t20 (hub specialist spawn) (2026-10-14)
- `SectorHub._spawn_patrol()` appends, after the four existing groups' nine rng draws, a Sniper (135 deg), a Bomber (45 deg) and a Ram Corvette (225 deg) on `specialist_ring_radius` (**1700**, the plan's start value - the live sweep did not need it raised). New exports: `specialist_ring_radius`, `sniper_anchor_bearing_deg`, `bomber_anchor_bearing_deg`, `ram_anchor_bearing_deg`. Each gets `patrol_anchor` and a nonzero `rng_seed` (draws 10-12) before `add_child()`; 315 deg stays free.
- Measured clearance (nearest interactable - `idle_radius` - `perceive_radius`): Sniper +144.6 px (`fortuna_station`), Bomber +252.8 px (`edelia`), Ram Corvette +308.7 px (`voeter_k05m`). The Sniper is the tightest: a pickup placed within ~145 px more of it fails `test_sector_hub_patrol.gd`.
- `test_sector_hub_patrol.gd`: three clearance rows, a boundary row (a pickup moved inside the sniper's reach is reported), seven anchors > 1000 px apart, seeds of the existing nine draws unchanged, container count and frame-0 IDLE list include the three, and a hub Bomber's mine lands in `EnemyContainer`. The clearance helper now returns violations, so the boundary row can assert one.

### Phase 4, built in t21 (level 1 Deep Space / Planet Approach specialists off rails) (2026-10-14)
- The 35 sniper / ram / bomber lines of `deep_space` (11) and `planet_approach` (24) lost `.move()`, `.free_after()` and `.shoot_at_player()`; trigger, offset and delay are unchanged (the t1 pin is green untouched). `cloud_descent` is still on rails (t22).
- **Measured exits, not straight lines:** `tests/helpers/specialist_exit_probe.gd` (`worst_disengage(host, scene, disengage_phase, speeds, cap)`) runs the real scene's DISENGAGE by hand-ticked `_physics_process` over the Ph3 404-start grid at three speeds (the ship's fastest DISENGAGE-entry speed, 10 px/s, 2 px/s; review N3). Slowest: sniper 5.40 s, bomber 7.98 s, ram curved 6.35 s (> the straight 4.55 s, so the curved term binds for the ram). Built for t22's deadline rows to reuse.
- Lifetimes: sniper `engage + aim + lock + 2 ticks + exit` = 16.23 s; bomber `engage + run_length/run_speed + RUN_STALL_SLACK + 2 ticks + exit` = 18.38 s; ram `engage + wind_up + charge_max_time + 2 ticks + max(straight, curved)` = 12.98 s. Spawn moments use the running-max effective trigger.
- **Count gate:** peak alive specialists deep_space 6 (limit 12.5 = 2.5 x 5), planet_approach 6 (limit 7.5 = 2.5 x 3). **No lever applied**; every `*_config.tres` value is unchanged. planet_approach has a 1-ship margin: one more specialist at its 65.7 s peak is fine, a ram triple is not (the boundary row).
- Late spawns now live into the next section (deep_space's 29 s snipers ~16 s into asteroid_belt; planet_approach's 98 s bomber and 102.3 s rams ~5-8 s into cloud_descent), as the legacy rails did; the frozen constants were computed the same way (t21 review N6).
- `test_extra_rams_at_the_peak_break_the_frozen_constant` moved to cloud_descent, the only section still live-checked; `_RAIL_SECTIONS` is `[cloud_descent]`, `MIGRATED_SECTIONS` is `[deep_space, planet_approach]` - t22 moves cloud_descent across.

### Phase 4, built in t22 (level 1 Cloud Descent snipers and rams off rails) (2026-10-14)
- The 15 sniper / ram lines of `cloud_descent` (9 snipers, 6 rams) lost `.move()`, `.free_after()` and `.shoot_at_player()`; trigger, offset and delay unchanged. All 50 specialist rows of level 1 are off rails. Task plan `docs/plans/cmuyk2qqp009loa2xb1k3py8o/3-plan.md` (Revision 2, review round 2 APPROVED).
- **Deadline rows** (`test_engagement_deadline.gd`): per entry, `rel + engage + deferral + exit + 0.5 < 10`. Sniper deferral `aim + lock` (+2 ticks), exit 5.40 s measured on the view grid; worst row (the 63.2 s snipers) 3.93 s. Ram deferral `wind_up + charge_max_time` (+2 ticks), exit `max(world diagonal / exit_speed, measured curved)`.
- **The ram's curved exit is measured over a second start set**, `SpecialistExitProbe.corridor_starts(corridor, world)` (80 px over +-720 of the 1480 x 1480 `AssaultCorridorConstraint` rect, heading away from the tie-broken nearest world edge and +-45 deg, speeds max charge and 10 px/s; ~3 s). `worst_disengage()` takes it as an optional `start_set` argument; the default is still t21's view grid. Reason (t22 review B1): a ram can begin DISENGAGE anywhere in the corridor, and from corner-tie starts outside the view (e.g. offset (-480, -480) heading away from the left edge) its `v^2/a` turning circle holds it inside ~2 s longer than anything on the view grid: 5.77 s vs 3.72 s at exit_speed 560 (6.48 vs 6.35 at 500). The sniper's corridor-wide figure was measured once equal to its view-grid one (5.40 s), so it stays on the view grid.
- **Both pre-approved ram levers applied, in order, each because the 73.2 s row still failed:** shipped (exit 500, engage 4.5) 10.82 s; `exit_speed` 560: 10.10 s; `engage_seconds` 4.0: **9.60 s (margin 0.40 s)**. The t17 attack-in-budget row stays green at 4.0: latest WIND_UP 3.07 s (0.93 s of budget left), one charge per life from every level-1 spawn class. The formula is pessimistic (it stacks the charge deferral onto the curved exit, which only ever follows a WIND_UP-then-STAGGER); its realisable split computes 8.55 s and is printed, not asserted. `ram_corvette_config.tres` and the `.gd` defaults now read 4.0 / 560; this also shortens ram lives in deep_space / planet_approach.
- Boundaries: a ram at 76.0 + 1.2 s computes 13.6 s; a ram forced to expire on its first LINE_UP tick (every cloud_descent offset) never winds up and is out of the world within 2.5-4.8 s (bound 9.80 s); a Bomber added to an ENEMIES_CLEARED last wave computes >= 10.90 s with no exit term at all (asserted for cloud_descent, reported for station_assault's 180 s net — a deliberate reading of "any section"), and no ENEMIES_CLEARED section contains one. If the t21 bomber lever (engage 6.5) is ever applied, the bomber row stops flagging and fails loudly.
- **Count gate:** cloud_descent joined `MIGRATED_SECTIONS` (peak 6 at 32.0 s with the final ram config — 7 before the levers — limit 10 = 2.5 x 4); `_RAIL_SECTIONS` is `[]` and `test_extra_rams_at_the_peak_break_the_frozen_constant` was deleted (the Ph3 t17 shape) — `_rail_lifetime()`'s sampling branch is now exercised by nothing.
- **Real replay:** new `tests/integration/test_level1_specialist_exit.gd` replays the whole section from 0.0 s (epic review N2) with only its snipers and rams, at 8x clock: all 9 + 6 spawn, every one leaves in DISENGAGE with no `EnemyPathMover`, and the container is empty 2.60 s after `waves_complete` (margin 7.40 s; last ram out 2.58 s after it). `test_level1_fighter_exit.gd` (from 66.0 s, the 73.2 s ram now on AI) empties 8.18 s after it (margin 1.82 s). Full gate 1593 tests, GUT time 256.8 s (was ~240 s).
- **Follow-up (not changed here):** the t21 count gate in `test_level1_specialist_spawns.gd` still uses the view-grid exits, so its ram life under-reports by ~1.7 s (12.98 -> with the new config about 10.2 s view vs 11.9 s corridor); every section's peak has slack against it.

## Phase 4 - as built (2026-10-14)

All 23 build-sequence keys of `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (**Revision 2**) landed on `agent/auto-dev`:
t1-t22 plus this t23 (docs). Preparation was research -> plan (Revision 1, round-1 review CHANGES_REQUESTED, 15 findings) ->
Revision 2 (round-2 review **CHANGES_REQUESTED**: B1 the mine wall cannot hurt a player who holds course, B2 `ArmorPlate`
depends on physics-callback order, plus N1-N10). The owner started the epic without a re-plan, so B1 and B2 were applied by
the tasks they named (t4/t6 for B2 and B1b, t9/t10 for B1). Six build tasks (t10, t13, t16, t17, t21, t22) were planned and independently reviewed on their own under `docs/plans/cmuyk2qq…/`, each but t21 CHANGES_REQUESTED at least once
before APPROVED (t21 was approved first time); t10 took six attempts (the last for the gate's wall-clock cap, see below). `docs/epics-done/cmufs7ele0015nm2xvag3vrwc/`
holds the dossier (PRD / SOURCES / REPORT). The per-task "built in tX" notes above are the detail; this section is the
index a later phase should read first. **Where a per-task note and this section differ, this section wins.**

### What was actually built

- **Primitives (all pure or `RefCounted`; none moves a node).** `Steering.break_contact` / `EnemyMover.break_contact`;
  `LineOfSight` (`global/enemy_ai/line_of_sight.gd`) and a real `TargetInfo.line_of_sight()`; `BulletPool.persist_after_owner_death`
  (`_hand_over_active()`); `ArmorQuery` and `ArmorPlate` (`global/components/`); `ContactProfile.Mode.ARMOR` with `shove_speed`;
  `OpenSpacePlayerShip.apply_knockback()`; `Bullet.is_high_impact()`; `ArmorQuery` called from `bullet.gd`, `homing_missile.gd`
  and `warhead_missile.gd`; the duck-typed `homing_point(from)` read by `homing_missile._fly_to_target`.
- **Enemy ordnance** (`assault/scenes/projectiles/enemy_ordnance/`): `EnemyOrdnance` (`Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`),
  three scenes, `EnemyOrdnanceScenes`. Not an `EnemyBullet`, not in `enemies`, never scored; any player hit defuses it.
- **The Bomber** (`assault/scenes/enemies/bomber/`): `Bomber`, `BomberBrain` (`APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE`
  then hub `IDLE, NOTICING, RETURNING`), flat `BomberConfig`, three `persist_after_owner_death` pools (4 / 10 / 4) and
  `Bomber.drop()`. Old `bomb.gd` / `bomb.tscn` deleted. Rail fallback: a gravity bomb DOWN every 1.2 s.
- **The Sniper** (`.../sniper/`, a `git mv` of `sniper_enemy/`): `Sniper`, `SniperBrain` (`ENTER, BREAK_CONTACT, RELOCATE,
  SETTLE, DECOY, AIM, LOCK, FIRE, DISENGAGE`, hub phases 9-11), `SniperTelegraph`, flat `SniperConfig`, a `RailPool` of 2,
  `rail_round.tscn` (`EnemyRounds.RAIL`) and `RailTrail`. `enemy_sniper_bullet.tscn` and every fly-in constant are gone.
- **The Ram Corvette** (`.../ram_corvette/`, a `git mv` of `ram_ship/`): `RamCorvette`, `RamCorvetteBrain` (`APPROACH, LINE_UP,
  WIND_UP, CHARGE, WIDE_TURN, DISENGAGE, STAGGER`, hub phases 7-9), flat `RamCorvetteConfig`, three `ArmorPlate`s under `Plates`,
  the ARMOR contact profile. Group `ram_ships` and the old layer immunity are gone.
- **Art.** `bomber.png` (104x56, overwritten in place), `sniper.png` (48x64) + `sniper_barrel.png` (8x42), `ram_corvette.png`
  (84x84) + `ram_plate_front.png` / `ram_plate_side.png`. `ram_ship.png` / `ram_ship_damaged.png` deleted.
- **Open Space.** `SectorHub._spawn_patrol()` adds a Sniper (135 deg), a Bomber (45 deg) and a Ram Corvette (225 deg) on a
  1700 px ring, drawn from the seeded rng after the existing groups' nine draws.
- **Level 1.** All 50 sniper / ram / bomber lines (26 / 22 / 2) are AI spawns: no `.move()`, `.free_after()` or `.shoot_at_player()`.
  Triggers, offsets and delays are unchanged and pinned. **Nothing in level 1 flies a rail of these three any more.** Only the
  station's reinforcements still fly rails (fighters and Gatlings).
- **Gates added or extended:** `test_level1_specialist_spawns.gd` (pin + count), `test_engagement_deadline.gd` (sniper and ram
  rows, Bomber boundary), `test_level1_specialist_exit.gd` (real `WaveManager` replay), an attack-in-budget row in each of
  `test_sniper.gd` / `test_ram_corvette.gd` / `test_bomber.gd`, `test_armor_query.gd`, `test_enemy_ordnance.gd`,
  `test_line_of_sight.gd`, `test_bullet_pool.gd`, the ARMOR rows of `test_contact_profile.gd`, `test_sector_hub_patrol.gd` (three
  more clearance rows), and `tests/helpers/specialist_exit_probe.gd`. The gate ends at **1593 tests, GUT time 256.8 s**, with
  `scripts/check-test-leaks.sh` clean.

### Deviations from `3-plan.md` (every one that a later phase can depend on)

| # | Plan said | What was built | Why / consequence |
|---|---|---|---|
| 1 | §2.3 mine warning 0.5 s | **`mine_warning` 0.25 s**, asserted `(trigger_radius + blast) / warning >= mine_speed_max` | Review B1(a): at 0.5 s a player at normal speed is past the blast before it fires. |
| 2 | §2.4 mine wall lead: bomber-timeline lead, middle mine armed `wall_margin` before the player's trigger edge | Same, plus `(trigger_radius + arc_depth) / |v|` (B1c); the mine arms from `launch()` and the trigger is a **poll** of `get_overlapping_areas()` (B1b) | A player already inside the radius at arm time still sets it off. |
| 3 | R4.5 "boosting right -> mine chain" | **A boosting player (> 440 px/s) gets a pursuit bomb, never a mine chain** | B1(e): a wall for a boosting player needs a lead longer than `mine_horizon`. Owner question for Ph16. |
| 4 | §2.4 arrival by the Fighter's fixed-point iteration | Earliest-feasible **scan** (T in 0.1 s steps to `approach_cap`, then 5 bisections) | The iteration diverged from a standing start. Tracked path replaced only when its goal moves > 24 px or the bomber is > 40 px off. |
| 5 | §2.4 angled line takes the side toward the heading | The side with the **shorter lead-in** (the heading / corridor / rng rule is the tie-break); the angle narrows 35 -> 0 deg to the widest loop-free one; `gravity_release_lead` **120** (was 80) | A bomber within ~880 px of P-hat sat beside the line's start at 35 deg and could only loop (~6.4 s). |
| 6 | (not planned) | **Line capture**: within 96 px / 45 deg of the line the bomber pursues a point 80 px ahead on it | A re-plan near the line produced a loop. |
| 7 | §2.2.4 plate damages itself in `area_entered`, `deflects_hit` from live state | One **idempotent `_resolve(hit_box)`** called from both | Review B2: "the breaking rocket is consumed" depended on Godot's undefined callback order. Ph10 keeps this shape. |
| 8 | §2.6 hull exposed on the last `plate_broken` | **Exposure deferred** to the end of that physics step (`call_deferred("_expose")`); `armor_broken` fires once, one step later | A rocket that breaks the last plate while overlapping the hull must not also land on it. Hang glow / stagger / disarm off `armor_broken`. |
| 9 | §2.6 `RamCorvetteBrain.Phase` | `STAGGER` **appended** after `DISENGAGE` (value 6) | Keeps t16's values; hub phases 7-9. |
| 10 | Ram attack gate `remaining() >= line_up_cap` | `>= line_up_cap + ATTACK_GATE_MARGIN` (0.05 s) | The budget updates before the phase logic; a LINE_UP started at exactly 0.5 s left could expire on its last tick. |
| 11 | WIDE_TURN ends -> LINE_UP | -> LINE_UP only inside `engage_range` and with the gate open, else APPROACH; capped at 4 s | A charge can end ~900 px out; a circling player could hold the turn forever. |
| 12 | Ram `engage_seconds` 4.5, `exit_speed` 500; first lever `exit_speed` -> 600 | **4.0 and 560** (both pre-approved levers, in order) | Cloud Descent's 73.2 s ram: 10.82 s shipped, 10.10 s at 560, **9.60 s at 4.0 (margin 0.40 s)**. 560 was enough, so 600 was not needed. |
| 13 | Ram exit measured over the Ph3 view grid | A second start set, **`SpecialistExitProbe.corridor_starts()`** (the whole 1480 x 1480 corridor) | The view grid under-reports the ram's curved exit by ~2 s (5.77 s vs 3.72 s at 560). |
| 14 | §2.5 ENTER -> BREAK_CONTACT | **ENTER -> SETTLE**; BREAK_CONTACT only after a shot or a refusal | ENTER is the seek to the first firing point; there is nothing to break from. |
| 15 | BREAK_CONTACT "until 0.9 x range" | At least **`break_min` 1.0 s** | After FIRE the sniper is already at range and the rule would end on its first tick. |
| 16 | Firing-point filters: Assault inset, forward cone, LOS | **Added the path-clearance filter** (`pass_clearance_ratio` 0.45 x range) and tiers A/B/C (A = `min_bearing_change` + 5 deg slack) | With the epic's weights the separation term always won and the straight RELOCATE flew through the player. |
| 17 | RELOCATE re-pick after a flat `relocate_cap` 4 s | Per trip: `max(relocate_cap, trip / relocate_speed + 1 s)` | The flat cap re-picked most Open Space trips (1500-1800 px) mid-route. |
| 18 | LOS checked from the firing point | LOCK re-checks on **two lines** (muzzle -> player and muzzle -> lock point); each refusal counted in `refusals` | A rock can block the locked line without blocking the player. |
| 19 | `SniperConfig` fields as §2.5 | **+ `rail_fallback_damage` 25** and the t13 fields (`break_min`, `velocity_smoothing`, `frame_speed`, `forward_cone_speed`, `seed_jitter`, `random_candidates`, `max_los_rays`, `pass_clearance_ratio`, `barrel_*_seconds`) | The rail fallback fires the legacy 1400 px/s shot at the legacy damage; the AI round's is 28. |
| 20 | Decoy line aims at the fake direction | The sniper keeps **facing the player** in DECOY; only the line is rotated (25-35 deg, side by coin flip) | Turning would move the muzzle off the measured bearing; the barrel art was not final. A budget expiry in DECOY disengages at once. |
| 21 | Sniper Shot breaks a plate in two hits | Confirmed with the mode's 40 damage: **two shots break a 50 HP plate** (the scene's own damage is 50, the weapon mode sets 40) | The mode `.tres` decides the real figure. |
| 22 | `RamCorvetteConfig.movement_speed` | **Removed** (nothing read it) | `BomberConfig.movement_speed` / `bomb_interval` likewise gone; `rail_bomb_interval` replaces the latter. |
| 23 | Sniper art nose-down | **Nose-up**, `sprite_forward_angle = -PI / 2`; hull 34 px wide against the ~40 px planned | The scene's muzzle and barrel sit at -Y and the old sprite was also nose-up. |
| 24 | Ram plates generated | Plates **drawn by script** (hull from PixelLab) | The generated slab came with a painted-on orange strip that fights `set_glow()`'s tint. |
| 25 | `persist_after_owner_death` in Ph5 | **Built in Ph4** (planned change, X1) | Mines and bombs need it. Ph5 builds owner-distance lifetime on it. |
| 26 | Heavy Shell first consumer in Ph4 | **Still none** (Ph10) | Neither the Bomber nor the Ram fires a round. |
| 27 | t21 count gate: view-grid exits for every specialist | Unchanged; the ram's life under-reports by ~1.7 s | See open items. Every section's peak has slack. |
| 28 | Gate time | Real-physics rows run on an **8x clock** with the step kept at 1/60 game-second | The harness cuts verification at ~300 s; at 1x the t10 rows took the gate to 348 s. |

### Conventions a later phase must keep

(In addition to the "Conventions" list planned above, which all stand.)

- **Armour is parts, not a mask.** An armoured enemy has one full-size `HurtBox`, `is_armored()` / `deflects_hit()`, and
  `ArmorPlate`s under a group node. Never narrow the hurtbox. Any later armoured entity uses `ArmorQuery`'s two duck types; a
  heavy player weapon opts in to breaking parts with `is_high_impact()`.
- **A breakable part resolves each hit once** (`ArmorPlate._resolve`, per HitBox instance id).
- **Persistent ordnance has its own lifetime cap and never enters `enemies` or `ScoreTracker`.** A Bomber never spawns in an
  `ENEMIES_CLEARED` section. Ph7's Mine Layer extends `EnemyOrdnance`.
- **A budgeted specialist proves it attacks (attack-in-budget row)** from every level-1 spawn class through a real
  `WaveManager`; a density or deadline lever is legal only while those rows stay green.
- **A telegraphed attack is never cut off by the budget, and a decoy is CHARGING-only.**
- **A ram's exit gate uses the corridor-wide curved bound**, a sniper's and a bomber's the view-grid bound (measured once equal
  for the sniper).
- **A test that awaits real physics scales the clock** (`Engine.time_scale`, `physics_ticks_per_second` and
  `max_physics_steps_per_frame` together, restored in `after_each`): the gate has a ~300 s wall-clock cap, now at ~257 s.
- **Rail fallbacks are mandatory** for a shooter or area-denier moved to a brain (the Ph3 rule): sniper cycle, bomber bombs, ram contact.

### Open items - nothing here is decided

- **Thin margin:** the 73.2 s ram row passes by **0.40 s** (9.60 s of 10). Any further ram retune (`acceleration`, `stagger_seconds`,
  `exit_speed`, `engage_seconds`) must re-run `test_engagement_deadline.gd`. The formula is pessimistic (a realisable split
  computes 8.55 s, printed not asserted).
- **Crowding count gate still uses view-grid exits** (`test_level1_specialist_spawns.gd`), so a ram's life is under-reported by
  ~1.7 s; peaks 6 / 6 / 6 against limits 12.5 / 7.5 / 10 (planet_approach is the 1-ship-margin section).
- **Sniper aims from where it settled** (review round 2, N2): the later re-pick means a sniper can aim from a point a boosting
  player has left far behind; nothing checks the range before AIM.
- **A boosting player gets no mine wall** (deviation 3). Ph16 owns whether that is acceptable.
- **A `RailTrail` is a child of the `EnemyContainer`**, so it can hold an `ENEMIES_CLEARED` section open up to `trail_fade` (0.4 s)
  after the last sniper leaves; cloud_descent's sniper rows have 6 s of margin so this is covered.
- **`LineOfSight` has no shipped blocker beyond asteroids.** The hub has no physics bodies, so the sniper's refusal is proven by
  fixtures only; Ph6 wrecks and Ph19 heavy ships plug in via `blocks_line_of_sight()`.
- **The space station has no `homing_point`**, so a rocket deflected by its armoured core still parks there (Ph11).
- **Two unrelated mine concepts exist** (`assault/scenes/race/track/mine.gd`, group `mines`, and enemy ordnance mines). Not touched.
- **`DefenseProfile.apply_alternate()` has no shipped user** after Ph4 (tested on `fixture_enemy.tscn`); Ph17 may delete it.
- **A warhead-friendly Assault ram** (`assault_plate_count` 1) was not built; one homing volley strips all three plates, a frontal
  warhead volley strips one.
- **Not play-tested (the gate cannot see it):** whether the sniper's 0.5 s lock reads as a fair window at Assault speed; whether
  the decoy reads as a bluff and never a lock; whether the mine wall is dodgeable by feel at 150-440 px/s; whether the ram's glow,
  plate break and charge read; whether the Sniper's barrel unfolding and its art (the barrel covers the hull's red spine panel)
  look right in motion; whether level 1's density feels right with specialists living their budget plus a curved exit instead of a
  rail's on-screen time; whether Open Space's noticing / return is calm.

### Handed to later phases

| Item | Phase | Note |
|---|---|---|
| Owner-distance lifetime, enemy rockets | Ph5 | Built on `persist_after_owner_death`; the round family still vanishes with its shooter. |
| Mine variants, minefields, the Mine Layer | Ph7 | Extend `EnemyOrdnance`; reuse the undamped wall-lead rule. |
| LOS blockers in shipped content | Ph6 / Ph19 | Answer `blocks_line_of_sight()`. |
| Modular damage beyond three plates, per-plate weapons | Ph10 | Extend or compose `ArmorPlate`. Heavy Shell's first consumer is the Heavy Gunship. |
| Station `homing_point` | Ph11 | |
| Squad messages (the sniper marking the player for fighters) | Ph14 | |
| Difficulty tiers: shorten `aim_seconds`, never `lock_seconds`; the decoy flag; the boosting-player wall | Ph16 | |
| Deleting `DefenseProfile.apply_alternate()`, recolouring legacy bullets, enemy SFX / VFX | Ph17 | |
| Taking the station's reinforcements and `level_2_waves.gd` off rails | Ph15 | The rail fallbacks are the contract. |
| Re-measuring the crowding count gate with corridor-wide exits | any phase retuning specialist lifetimes | |

## Phase 5 - Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship (2026-10-15)

Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` (**Revision 2**, answering the round-1 plan review in `4-review.md`),
with research in `1-context.md` and `2-research.md` in the same directory. These are *planned* decisions; check this
phase's *as built* section, once written, before relying on them. (This section replaces the Revision 1 section of
2026-10-14.)

### Changes to earlier decisions
- **P-15 closed: `BaseEnemy` does not adopt `DamageReaction`.** It hears `received_damage(damage)` with no hit, so it cannot
  express a directional or projected shield; its `Shield` is a player resource; swapping ~12 enemies' flows gains nothing
  visible. `DamageReaction` stays a racer component.
- **Owner-distance lifetime (`max_distance_from_owner`, assigned to Ph5 by Ph1, restated by Ph4) is not built.** Every
  rocket is bounded by `max_time` and `max_distance` from its origin, and a projectile that outlives its owner has nothing
  to measure from. Handed to Ph13 with `max_distance_from_player` if encounter ownership needs it.
- **`BulletPool` container injection is deferred again** (Ph2 → Ph5 → Ph10): every pool here is a direct root child and
  cluster submunitions are unpooled. The first nested launcher (Carrier hangars) owns it.
- **Enemy friendly fire is decided for rockets only:** a rocket's **impact** hurts enemies, enemy ordnance, Ram plates
  and asteroids; its **blast** (`ContactBlast`) is the only thing that hurts the player or allies. Blasts and beams in
  general: still undecided (Ph8).
- **Enemy rockets wear down Ram Corvette plates** (plates break on `ROCKET`; 50 HP = 3–4 rockets) — accepted counterplay,
  pinned by a test (owner question 1, default yes).
- **Rocket tuning lives in each rocket scene's exports, not in the launcher's config** (unlike Ph4, where `BomberConfig`
  carries its ordnance numbers): Ph10's Carrier missile bank and Ph11's fortress launcher will fire the same rockets, and a
  rocket kind should be identical whoever fires it. Ph16 scales a rocket by setting exports before `launch()`.
- **The `player_rockets` layer (bit 32) is not renamed**, though enemy rockets' impact HitBoxes now sit on it (alone); the
  constant's doc says so.
- **Gate time is a budgeted resource from this phase on.** Measured at `7916662`: import 4.7 s, boot 1.0 s, GUT 253.3 s
  against a ~300 s harness wall-clock cap. Phase 5's first task (a dependency of every other) frees ≥ 70 s (GUT ≤ 183 s)
  without weakening any test and adds `scripts/gate-time.sh`; every later task stays within a per-task allotment (56.5 s
  total for this epic) and keeps **GUT ≤ 240 s**. Later phases should budget the same way.

### Names and places later phases build on
- **`HurtBox` absorb hook** (`global/components/hurtbox_component.gd`): `set_absorber(obj) -> bool` (one slot; false when a
  live absorber holds it), `clear_absorber(obj)`, `has_absorber()`, `signal hit_absorbed(hit_box: HitBox)`. An absorber
  answers duck-typed `absorbs_hit(hit_box: HitBox) -> bool`; on true the hurtbox emits `hit_absorbed` instead of
  `received_damage`. No absorber = byte-identical. **This is the hit-aware damage decision point for shields**; Ph10 module
  shields and Ph11 shield nodes attach here, not by narrowing masks.
- **`EnemyShield`** (`global/components/enemy_shield.gd`, `Node2D`): `arc_deg` (≥ 360 = bubble; may change while attached),
  `capacity` (points; a hit subtracts its damage; the breaking hit is absorbed whole), `regen_delay`, `regen_seconds`,
  `reboot_seconds`, `turn_rate`, `radius`, `sustain_mode` + `heartbeat` + `fade_seconds`; `attach(hurt_box)`,
  `set_threat_point()`, `sustain(threat_point)`, `absorbs_hit()`, `points()`, `is_up()`, `facing()`; signals
  `absorbed(hit_box, remaining)`, `broken()`, `restored()`, `lapsed()`. Cyan, drawn in world angles, never writes
  `rotation`. **It never absorbs while its host answers the hit-blind `is_armored() == true`**, and never calls
  `deflects_hit()` (an `ArmorPlate`'s resolves and damages the plate).
- **An absorbed hit consumes the bullet** (it is not a deflection; a pierce charge is spent). **Direct emitters** (beam,
  nova, dash, shield overload, engine boost, laser ray) bypass shields exactly as they bypass plates.
- **`BaseEnemy`**: hit flash / burst only when health went **down**; `repair(amount) -> int`; `can_be_repaired()` (station:
  false; Support Ship: false); `is_ai_driven()` (brain and mover present, not suspended); `accept_tow(v) -> bool` (a nudge
  on the enemy's own mover; false unless `is_ai_driven()`, not boosting and `brain.accepts_tow()`);
  `ai_mover_max_speed()`. A later "pull" or "push" between enemies goes through `accept_tow`, never a velocity write.
- **`EnemyBrain.accepts_tow() -> bool`** (default true): false in every committed or telegraphed phase — Sniper
  DECOY/AIM/LOCK/FIRE, Ram WIND_UP/CHARGE, Bomber RUN, Fighter RUN_IN, Gatling SPIN_UP/STREAM, Razor
  WINDUP/DASH/FEINT_WINDUP/FEINT_LUNGE, Swarm WINDUP/BURST, Missile Corvette TELEGRAPH/SALVO. **Every new brain with a
  telegraphed attack must override it**: a telegraph is never moved by anyone but its own brain.
- **`EnemyWorld.has_view_rect(tree)` / `view_rect(tree)`**, backed by `ArenaCamera.enemy_view_rect()` (centre
  `global_position + offset`, size viewport / zoom; never `get_screen_center_position()`, which is stale in hand-ticked
  tests): the rect the Assault camera shows **now**, as opposed to the 1480 × 1480 corridor.
- **Rocket family** `assault/scenes/projectiles/enemy_rockets/`: `EnemyRocket extends Area2D`,
  `Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`, `launch(dir, aim_point, launcher)`, `reset()`, `expired`;
  `EnemyRocketScenes.scene_for(kind)` / `pool_size_for(kind, cfg)` (`count × ceil(max_time / salvo_period_min)`, count =
  `warhead_salvo_count` for WARHEAD else `salvo_count`).
  - **Layers:** impact HitBox on layer **32 only**, mask **640** (128 | 512, no environment bit), `ROCKET`; shoot-down
    HurtBox layer 512, mask **96**, resolved by the rocket's own `area_entered` handler (never `received_damage`),
    ignoring any `EnemyRocket` HitBox. Blast = `ContactBlast` on 256.
  - **One player-facing damage source:** the player and allies take only `blast_damage` (direct hit or near miss alike —
    one hit against the player's 0.5 s i-frames, one shield charge). Enemies, plates, ordnance and asteroids take only
    `impact_damage`. An armoured hull lets a rocket through (`ArmorQuery.deflects`).
  - **Shoot-down:** a player bullet or player homing / warhead missile and an enemy rocket destroy each other, no blast.
    Rockets ignore each other.
  - **Launch safety:** a launcher answers duck-typed `launch_velocity() -> Vector2` (the rocket inherits its component
    along the launch direction; on a rail, the observed position delta) and `rocket_clear_radius() -> float`. The rocket
    arms when clear of the launcher's **current** position by `rocket_clear_radius() + body_radius + arm_clearance`; the
    rocket alone owns this rule. Invariants: every rocket `cruise_speed ≥ 1.1 ×` its launcher's `max_speed`, `launch_speed
    > launcher acceleration × boost_seconds`.
  - **Art is nose-up** (`rotation = heading.angle() + PI / 2`, the player missiles' convention), so `RocketTrail`'s local
    +Y is the tail. Enemy ship hulls stay nose-down.
  - Guidance = lead pursuit on `TargetInfo.intercept()` capped at `lead_max`, `Steering.turn_toward` at `turn_rate`,
    finite `guidance_seconds`, then coast. Cluster splits **by distance** (or `split_time`) into unpooled self-freeing
    submunitions; shot before the split leaves nothing. Warhead **stops dead on trigger** and uses the Ph4 mine rule
    `(trigger + blast) / warning ≥ 420`. Lifetime expiry fizzles (no blast). Not in `enemies`, never scored, per-kind rows
    in `test_enemy_bullet_lifetime.gd` (never in `_every_shipped_enemy_bullet_speed()`).
- **Missile Corvette** `assault/scenes/enemies/missile_corvette/` (`MissileCorvette`, `MissileCorvetteBrain`,
  `MissileCorvetteConfig`): `Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }`;
  `fire(kind, aim_point) -> EnemyRocket` (sets no rocket field); `salvo_size(kind)` (3, or 2 Warheads); four
  persist-after-owner-death pools (3/6/3/4); launch cone 45°; StateLight CHARGING / ARMED, never COMMIT; rail fallback = a
  Dumb rocket DOWN every 2.5 s. `WaveBuilder.missile_corvette()`.
- **Support Ship** `assault/scenes/enemies/support_ship/` (`SupportShip`, `SupportShipBrain`, `SupportShipConfig`):
  `Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`; contact profile `NONE`; ward claim =
  meta `&"support_claim"` on the ward (one support per ward); `ward_changed(new_ward)`; `is_supporting()`; the projected
  shield is an `EnemyShield` child of the ward named `ProjectedShield`, in sustain mode, owned by the ward and lapsing when
  the support stops feeding it (death, EMP, range, view, switch); **widened to a 360° bubble during ESCORT**.
  `WaveBuilder.support_ship()`.
- **Ward rules:** candidates are live `BaseEnemy`s in `enemies` that are `is_ai_driven()`, `counts_toward_wave_clear` and
  `score_value ≥ ward_min_score` (20), never another support — so the gunship, station, bonus drone and swarm drones are
  never wards, and every ward is escort-capable. Threat = `score_value × 1/(1 + d_player/600) × (1 + damage fraction)`;
  hold ≥ 2 s, switch at ≥ 1.3×; a lost ward is replaced on the next tick. Repair: pulses of 6 % max HP every 1.5 s,
  150 HP budget per life, hull `Health` only (Ram plates never), supports never repair supports. Escort: at ≤ 35 % HP,
  tow 1.25 × the ward's max speed away from the player via `accept_tow` (refused during the ward's telegraphs; the
  support then only interposes), support interposes; ends at 50 %, 700 px, 4 s; 6 s cooldown per ward.

### Conventions
- **Assault:** neither enemy goes into an `ENEMIES_CLEARED` section (corvette rockets persist; guard rows for both).
  Both count as **specialists** in `test_level1_specialist_spawns.gd`'s frozen 2.5× gate. Both have attack-in-budget rows
  (corvette: TELEGRAPH + a salvo; support: a projected shield on a ward). No lever on an existing enemy is pre-approved for
  placing them; a placement that breaks a gate moves its own trigger or escalates.
- **The support cannot hide above the camera:** its anchor is clamped into `view_rect().grow(−48)` and it supports only
  while inside `view_rect().grow(24)`.
- **Hub:** the corvette takes 315° on a new 1900 px ring (+417 px clearance); the support shares the Ram Corvette's
  anchor; draws 13 and 14 after the existing 12. Radii (perceive / lose): corvette 720 / 1500, support 600 / 1300.
- **Gate time:** `scripts/gate-time.sh` before and after every task; a test that awaits real physics runs on the 8× clock;
  a hand-ticked scenario several tests replay is computed once; over-allotment is fixed by sharing work, never by
  cutting an assertion.
- **Gate time, t1 as built:** GUT 253.4 s → 176.9 s (−76.5 s; wall 257.5 → 181.0), 1593 tests / 68619 asserts unchanged. 8× clock on
  `test_level1_fighter_exit`, `test_ram_corvette` (all rows), `test_level1_drone_exit`; `test_level1_fighter_fire_density` 4× → 8×
  except its 0.1 s wave-schedule row, which stays 4× (one 8× idle frame is ~0.13 s, so the tolerance would otherwise widen).
  `test_fighter_squad.gd` has nothing to compute once (58.9 of its 64.6 s is one 168-layout sweep, 53.6 s of it the fighters' own
  ticks), so the saving there is only ~1.7 s; the headroom is 6 s under the 183 s target, so later tasks must watch their allotments.
  Table in tests/README.md → "Gate time".
- **t2 as built (enemy shields; P-15 closed as planned: `BaseEnemy` does not adopt `DamageReaction`).** Choices t12/t13
  build on, beyond §2.3: `EnemyShield.face(world_dir)` snaps the facing and the **initial facing is `Vector2.DOWN`**, so a
  projector calls `face()` toward the player before its first `sustain()` (otherwise the arc needs ~2 s at 1.6 rad/s to
  swing round in Open Space); `restored()` fires on **every** refill to full, not only after a break; after a break the
  refill starts straight after `reboot_seconds` with no extra `regen_delay`, and the shield is `is_up()` only once
  `points()` (floored) is ≥ 1 (about 2 ticks after the reboot at the defaults); a sustained shield **releases the hurtbox
  slot at the lapse** (the fade is drawing only), so a support can attach a new shield to the same ward during the fade;
  `HurtBox.set_absorber` also refuses an object without `absorbs_hit`. **Limitation:** a shield does not cover an
  `ArmorPlate` (the plate damages itself in its own `area_entered`) — Ph10 module shields must go on a plain part's
  `HurtBox` (proven by the local-module fixture row). **For t12:** at the epic's `shield_capacity` 40 one Standard shot
  (50) breaks the projected shield, then 4 s of reboot — tune knowingly. Gate time: GUT 177.6 s → 176.9 s (the three files ≈ 1.4 s standalone, of the 3.0 s allotment, within run-to-run noise), 1593 → 1620 tests.
- **t3 as built (repair and tow hooks, no deviation).** `BaseEnemy.repair(amount) -> int`, `can_be_repaired()` (the station
  answers false), `is_ai_driven()`, `accept_tow(v) -> bool`, `ai_mover_max_speed()`; `_on_health_changed` flashes and bursts
  only when health went down (`_last_health`, unset = `max_health`). `EnemyBrain.accepts_tow()` (default true) is overridden in
  the seven shipped brains, each as a trailing `match phase` at the end of the file; t8 adds the Corvette's (TELEGRAPH, SALVO).
  The Ram boundary compares a towed run to an untowed twin (not an absolute position): the Ram crawls under its own brain.
- **t5 as built (Dumb + Pursuit rockets, `EnemyRocket` contract).** Choices t6–t8 build on, beyond §2.6/§2.7:
  (1) **no player → no turn**: guidance skips the tick entirely (Ph4's pursuit bomb steers at its stale target point
  instead; not changed). (2) **`launch()` re-applies** `impact_damage`, both shape radii (`body_radius`, hurtbox
  `+ 2`) and `max_time` / `max_distance` to the children, so exports set between `acquire()` and `launch()` (Ph16
  tiers, a test) take effect. (3) **The shoot-down also ignores `CONTACT`-type HitBoxes**: the ally fighter's ram box
  sits on layer 64, so without this an ally touching a rocket could defuse it (no blast) in an undefined callback
  order; now the ally detonates it through its 128 hurtbox and takes the blast, as the §2.6 table says. No player
  projectile is `CONTACT`. (4) **`expired` after a detonation or shoot-down goes out two physics ticks later** (the
  rocket hidden meanwhile), and `_mark_done()` disables both shapes as well as closing the areas: a `BulletPool`
  recycles by re-parenting, and `Area2D` re-emits `area_entered` for an overlapping area re-entering the tree until the
  server has delivered the exit (turning `monitorable` off alone keeps the pair) — recycling at once hit the enemy a
  second time (968 instead of 984 in the friendly-fire row). A lifetime fizzle still emits at once. A launcher that
  counts `expired` must allow the 2-tick lag. `EnemyRocket._tick(delta)` is the hand-tick entry (tests turn the
  rocket's and its `ProjectileLifetime`'s physics process off). Fixture launcher: `tests/helpers/rocket_launcher_fixture.gd`.
  Gate time: GUT 177.5 → 180.0 s (+2.5 of 6.0), `test_enemy_rockets.gd` 2.3 s / 16 tests.
- **t6 as built (Cluster Rocket, Submunition, Delayed Warhead).** Choices later tasks build on, beyond §2.8: (1) all
  of it lives in `enemy_rocket.gd` (one script, `kind` + exports; no per-kind subclass): `@export_group("Cluster")`
  (`split_distance` 260, `split_time` 2.0, `cluster_count` 4 in 3–5, `cluster_fan_deg` 36, `submunition_scene`) and
  `@export_group("Proximity")` (`trigger_radius` 70, `prox_arm_seconds` 0.6, `warning_time` 0.4); `reset()` restores them.
  (2) **A CLUSTER splits on the tick that *reaches* `split_time`** (`_clock + delta >= split_time`), before moving, so the
  split point is where the previous tick left it; distance splits when the player is within `split_distance` at the
  start of a tick (`<=`). (3) The parent's `_split()` is `_mark_done()` + children + pop + the same 2-tick-delayed
  `expired` as a detonation, with **no `ContactBlast`**; the children are instantiated into the parent's own
  `get_parent()` (the container), `reset()`, `expired -> queue_free`, `launch(dir, point, null)`. (4) The WARHEAD's trigger
  is the `ProximityArea` poll (`get_overlapping_areas()`, layer 128) once the clock reaches `prox_arm_seconds`; it stops
  dead (`_speed = 0`, `is_guiding()` false), `is_triggered()` is public, and it detonates when the warning clock reaches
  `warning_time`. The trigger sees **any layer-128 hurtbox, allies included** (the Ph4 mine does the same). (5)
  `EnemyRocketScenes` now maps CLUSTER / WARHEAD / SUBMUNITION; `pool_size_for` is unchanged (CLUSTER 3, WARHEAD 4);
  SUBMUNITION is never pooled. The launcher fixture pools CLUSTER and WARHEAD too. (6) The Warhead's 240 px/s cruise
  equals a shipped round speed, so `test_no_rocket_speed_is_in_the_round_speed_list` checks only its launch speed.
  Gate time: GUT 180.0 → 182.1 s (+2.1 of 4.0), `test_enemy_rockets.gd` 5.0 s / 25 tests; 1660 → 1670 tests.
- **t7 as built (Missile Corvette shell).** Choices t8–t16 build on, beyond §2.9: (1) **`launch_velocity()` on a rail is
  observed per PHYSICS tick, not in `_process`** (a deviation from §2.9's wording): `MissileCorvette` connects
  `SceneTree.physics_frame` and reads `(global_position − previous) / get_physics_process_delta_time()`
  (`_observe_motion(delta)` is the hand-stepping seam). A render frame holds zero or several ticks, so a per-frame
  reading was 300 instead of 330 px/s on the 8× clock and would read 0 on a 144 Hz frame with no tick; the railed row
  asserts (0, 330) ± 5. `_process` keeps only the rail fallback clock. (2) `StraightMovement.speed` is in design units
  (the rail doubles it by `WORLD_SCALE`), so the 330 px/s rail is `straight(165)`. (3) The brain ships `Phase`
  `{ APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }` already (append-only), plays only
  APPROACH and DISENGAGE, and has the `start_engaged` seam (unused until t15). `held_range()` is
  `assault_preferred_range` when the Assault budget is active, else `preferred_range`. `accepts_tow()` already refuses
  TELEGRAPH / SALVO. (4) The hull sprite is a **placeholder** (`ram_corvette.png`, until t9); the tube lamps
  (`Tubes/TubeLightL` / `TubeLightR`) take a radial texture built in code, driven by `set_tube_glow(0..1)`. (5)
  `test_enemy_rockets.gd` reads the launcher numbers from `missile_corvette_config.tres` (`_CORVETTE`), the
  constants are gone. (6) `fire()` counts a refused launch in `rockets_refused`; `BulletPool` logs its usual
  exhaustion warning.
- **t8 as built (Missile Corvette fight).** Task plan `docs/plans/cmv9szqlq001zqs2x6vi0nlxj/3-plan.md` (review round 2
  APPROVED). What later phases build on: (1) **`break_contact` side inside an orbit is `-orbit_dir`.** §2.10.2's "side =
  orbit direction" is read as *the sense the arc turns*: `Steering.break_contact`'s lateral is `away.orthogonal() × side`
  (−90° for +1) while `Steering.orbit`'s +1 travels +90°, so the literal `+orbit_dir` opposes the orbit (measured on a
  350 px/s rusher in Assault: closest pass 147 px literal, 250 px with `-orbit_dir`, 200 px with no blend). **Any later
  brain that blends `break_contact` into an orbit (the Support Ship's dodge, a hub idle) needs the same sign.** The blend
  is `orbit request + break_contact(max_speed)` in one `request_velocity`, capped by the mover. (2) `choose_kind(distance,
  player_speed, radial_speed)` takes a **required** third argument (radial = player velocity along corvette→player, > 0
  away); the 1-in-4 DUMB→PURSUIT swap is drawn outside it, at TELEGRAPH entry. (3) New public surface:
  `salvo_size(kind)`, `attack_window()` (from config, 1.14 s: the deferral bound and, + `ATTACK_GATE_MARGIN` 0.05, the
  gate), `in_launch_cone(point, cone_deg)`, `salvo_cooldown` (drawn at the first tick and after each salvo, so the first
  salvo comes 4–5 s after spawn: one salvo per Assault life at `engage_seconds` 7.0 — t17's attack-in-budget rows start
  from that), `orbit_dir`, `salvo_kind`, `salvos_fired`, test seam `force_next_kind(kind)`. HOLD_ARC never returns to
  APPROACH (the orbit anchor follows the player). (4) The Warhead pair's `across` is fixed once per salvo at SALVO entry
  (velocity perpendicular, or the line-of-sight perpendicular from the hull's centre). (5) The orbit drift starts at 0
  (sine phase 0 or π), period rng 6–9 s; reversals are an instant flip of the anchor's direction (no REVERSE phase).
  (6) `MissileCorvette.next_tube_position()` (read-only) and `EnemyRocketScenes.export_of(kind, property, fallback)` (any
  root export via `PackedScene.get_state()`; `max_time_of` now calls it and returns 4.0, not 0.0, for a kind with no
  scene). (7) The t7 approach row now asserts the APPROACH → HOLD_ARC hand-over within `range_tolerance` and the held
  band `R ± (range_drift + range_tolerance)`, not "parked within 25 px". Gate time: GUT 182.9 → 183.3 s (+0.4 of 5.0),
  `test_missile_corvette.gd` 16 → 37 tests in about 1.1 s; 1687 → 1708 tests.
- **t9 as built (Missile Corvette and rocket art).** `missile_corvette.png` is a PixelLab hull (flipped nose-down, baked
  engine flames removed) with the two launch tubes hand-drawn at the `Tubes/TubeL` / `TubeR` markers (local (±18, 30));
  the rockets are PixelLab sprites with their baked flames removed and the submunition hand-drawn (6 x 10). Later
  phases that fire these rockets need nothing: node names are unchanged, plus a new `Sprite2D` on every rocket scene and a
  `BlinkLight` `Sprite2D` on the warhead. **The look-only `body_color` export is gone** from `EnemyRocket` and its five
  scenes (the placeholder `_draw()` body went with it); `RocketTrail.offset_behind` is now per scene (12 / 12 / 12 / 5 / 9).
  PURSUIT shares `enemy_rocket.png` with DUMB and is told apart by a violet `modulate`. Rows: `test_enemy_rockets.gd`
  (sprite per kind, trail behind the nose for every kind and heading, warhead blink) and `test_missile_corvette.gd`
  (opaque art at each tube marker).
- **t10 as built (Support Ship shell).** Choices t11–t16 build on, beyond §2.11: (1) the brain ships `Phase`
  `{ SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }` already (append-only) and plays only SEEK_WARD and
  DISENGAGE; `brain.ward` is the ally it holds (`nearest_ally()`: nearest live `BaseEnemy` in group `enemies`, never a
  `SupportShip`), which t11 replaces with the scored ward choice. (2) The `Projector` is folded with `scale.y` 0; **Godot
  clamps a zero node scale to an epsilon (~1e-5)**, so rows compare with a tolerance, not `== 0.0`. `SupportShip.fold_projector()`
  folds it instantly and hides the tether (the `on_suspended()` path); t12 adds the animated unfold. (3) The contact hitbox is
  closed by the NONE profile with a *deferred* `monitoring`/`monitorable` write: a test that re-opens it must wait one physics frame
  first and assign directly (a `set_deferred` queued the same frame is overwritten). (4) Placeholder art: the hull is
  `sniper.png` and the projector `sniper_barrel.png` until t14. (5) `max_turn_rate` 4.0 x `exit_speed` 300 exceeds
  `acceleration` 700, so DISENGAGE curves at `min(max_turn_rate, acceleration / exit_speed)` (2.33 rad/s), as the Bomber's does.
- **t11 as built (Support Ship ward, follow, retarget, Assault clamp).** Task plan `docs/plans/cmv9szqlz002bqs2x0h47xa3x/3-plan.md`
  (review round 3 APPROVED). Choices t12–t17 build on, beyond §2.12: (1) `SupportShipBrain._set_ward()` is the **only writer** of
  `ward`, the claim meta (`CLAIM_META = &"support_claim"`, the claiming support's instance id; a stale id counts as free) and the
  ward's `tree_exiting` connection (the bound `Callable` is stored and the disconnect guarded). It emits
  `ward_changed(new_ward: Node)` on every change, so a loss then a re-pick emits `null`, then the new ward. Public state:
  `ward` (read via `has_ward()`), `ward_score`, `ward_held_for`, `wards_selected`, `anchor` (`Vector2.INF` with no ward),
  `follow_side`, `jink_sign`, `is_candidate()`, `threat_score()`, `best_candidate()`, `is_supporting()`, `nearest_ally()`.
  (2) Per tick: validate (drop) → select → phase (ward → FOLLOW, none → SEEK_WARD). A ward lost via `tree_exiting` is replaced on
  the next tick; one lost via validation (killed = queued, railed, beyond `ward_keep_radius`, out of `view.grow(ward_view_band)`)
  is replaced on the tick that sees it. (3) **The Assault no-ward grace runs only while the support is inside
  `view.grow(view_band)`** (supports and allies spawn above the screen; a clock from spawn would send a support home before its
  allies arrive). SEEK_WARD's hold point (the nearest ally's `follow_distance` point, or with no ally the support's own position)
  is clamped into `view.grow(−view_margin)` in Assault, so a support always comes into view and the clock always starts; the
  budget stays the backstop. **t17:** a support's first `is_supporting()` needs a candidate inside `view.grow(ward_view_band)`.
  (4) FOLLOW is one `request_velocity(seek + jink + evade)`, not `mover.arrive` alone: a full-speed arrive cancels a 60 px/s
  jink and a 240 px/s escape to a few px. Seek = `Steering.arrive` capped at `min(max_speed, d_anchor × FOLLOW_GAIN)`,
  `FOLLOW_GAIN` 2.0 /s (a spring near the anchor); jink = `jink_strength` px/s across the ward line, sign redrawn every
  `jink_period` (≈ ±25 px sway); inside `evade_radius` seek and jink are scaled by `w = clamp((d − 0.8R) / 0.2R, 0, 1)`, their
  toward-player component removed, and `break_contact(..., evade_speed, EVADE_LATERAL_WEIGHT 0.3)` added (the default 0.6,
  doubled for a closing threat, escapes at ≈ 154 px/s — slower than a 200 px/s player). All judgement, measured in
  `test_support_ship.gd`. (5) The t10 rows that assumed a score-0 fixture ally is held in Assault for > 1.5 s are Open Space
  only now (the SEEK_WARD fallback); `test_enemy_dual_mode.gd`'s support case uses a ward (`score_value = 25`).
- **t12 as built (Support Ship repair pulse and projected shield).** Choices t13–t17 build on, beyond §2.13: (1) all of it is in
  `SupportShipBrain._tick_support()`, called at the end of every `tick()` (also on the DISENGAGE paths, where the ward is null, so the
  dish folds). `is_supporting()` drives everything: the dish (`projector_open` 0..1, rising over `projector_unfold_seconds`, falling
  over `projector_fold_seconds`; `SupportShip.set_projector_open()` writes `scale.y` eased out), the tether (`show_tether()` /
  `hide_tether()`; cyan `TETHER_COLOR`, pale green `TETHER_REPAIR_COLOR` for 0.15 s after a pulse, alpha `TETHER_DIM_ALPHA` when
  `LineOfSight` is blocked), the pulse and the shield. (2) Repair: `_repair_clock` accumulates only while supporting; every
  `repair_period` one pulse of `max(1, round(max_health × repair_fraction))`, **clamped to the budget left** (so the total is exactly
  `repair_budget`, never over), skipped when the budget is spent, the line is blocked or `can_be_repaired()` is false. `repaired(ward,
  amount)` fires only when HP was actually gained (a pulse on a full-HP ward is silent and does not flash). `repair_spent` is public.
  (3) The shield: `_make_shield()` builds an `EnemyShield` named `ProjectedShield` (`sustain_mode`, arc 110 / Assault 90, config
  capacity / regen / reboot / turn rate, `radius` = the ward's body `CollisionShape2D` radius + 6, 34 + 6 with no body shape),
  `attach()`es it **before** `add_child` (false → freed, nothing added; retried next tick), faces it at the player at once, then
  `sustain(player_position)` every supporting tick. The brain's `shield` is only "one needs creating?" bookkeeping: cleared on a ward
  change and on the shield's `lapsed`. Nothing frees or detaches a shield explicitly: a support that dies, is EMP-disabled
  (`process_mode` DISABLED stops the brain tick), leaves range or view, or switches ward simply stops feeding it, and it lapses after
  `heartbeat` and releases the hurtbox slot (t13: widen `arc_deg` to 360 on `shield`, keep `sustain()`ing it). (4) The armoured-Ram
  row needs no support-side code: `EnemyShield.absorbs_hit` refuses while the host's `is_armored()`. (5) Test-only: a `BaseEnemy`
  whose HP is written directly (`health.current_health = x`) has an unset `_last_health`, so its first repair compares against
- **t13 as built (Support Ship emergency escort).** Choices t14–t17 build on, beyond §2.14: (1) ESCORT is entered from FOLLOW inside
  `tick()` (`_escort_due()`: ward HP fraction <= `escort_hp_ratio`, per-ward cooldown from `_escort_ready_at[ward_id]` read against the
  brain's accumulated `_clock`) and its first tick runs in the same call, so the tow lands on the tick after the HP drop. (2) Ends in
  `_tick_escort()` on release ratio (>=), `escort_safe_distance` (>=) or `_phase_time >= escort_max_seconds`, back to FOLLOW; a lost ward
  leaves ESCORT in `tick()`'s validity branch (retarget as before); DISENGAGE/budget expiry also leaves it. All exits go through
  `enter_phase()` / `_set_ward()`, which call `_end_escort_effects()` once (starts the ward's cooldown, gives the shield its mode arc).
  Ward switching is suspended while escorting. (3) The tow is `ward.accept_tow(away * escort_tow_ratio * ward.ai_mover_max_speed())` every
  tick; its refusal is ignored (the support just interposes). The interpose point is `ward - away * interpose_distance` (toward the
  player), `_clamp_into_view` in Assault, sought at `distance * ESCORT_GAIN (6)` capped at `max_speed`, no jink, no evasion. (4) The
  bubble: `_shield_arc()` is 360 during ESCORT, written onto `shield` every supporting tick and in `_make_shield()`; restored by
  `_end_escort_effects()` even when the support is no longer supporting. (5) `SupportShip.show_tether(to, color, towing)` draws the
  tow beam at `TOW_WIDTH_FACTOR` (2.5) x the scene width. (6) Test-only: a real Sniper settles beyond `escort_safe_distance` of a
  far player and, in Assault, above `ward_view_band`, so `test_support_ship.gd::_telegraph_run` lays the sniper row out horizontally and
  pulls the player to 400 px once LOCK begins.
  `max_health` and flashes; damage fixtures through `health.decrease()` (`test_support_ship.gd::_repair_world`).
- **t15 as built (hub idle for the Missile Corvette and the Support Ship).** Both brains follow the Ph4 Ram template (`AnchorIdle` ahead of
  the phase dispatch, `patrol_anchor` defaulting to the spawn, `idle_phase_offset` from `rng`, `start_engaged`; Assault builds no
  `AnchorIdle`; `on_suspended()` drops it). Choices later phases build on: (1) Corvette: IDLE / NOTICING / RETURNING are not entered from
  TELEGRAPH or SALVO (retried each tick); every calm entry resets the arc (`_orbit_synced`, `_breaking`) and stops the burst, and NOTICING
  redraws `salvo_cooldown`, so a corvette that has idled for a minute does not fire the instant it notices the player. (2) Support: no
  protected phase; entering any calm phase calls `_set_ward(null)` (which ends an ESCORT's effects once), and the calm phases skip ward
  selection entirely (`tick()` returns after `_tick_support`, which folds the dish). (3) Idle orbits run at the config's `max_speed`; the
  corvette overshoots its ring by ~40 px for the first ~3 s when it starts on the anchor (240 px/s² acceleration), settling at 149 px, so the
  ring row measures after 4 s. (4) Every earlier Open Space spawn in the suite sets `start_engaged` (`# pre-t15`); the real hub spawns are t16.
- **t16 as built (hub placement).** `sector_hub.gd` `_spawn_patrol()` appends, after the twelve earlier draws: a Missile Corvette at 315 deg on the new `missile_corvette_ring_radius` 1900 ring (`missile_corvette_anchor_bearing_deg`; draw 13; +417 px clearance) and a Support Ship on the Ram Corvette's anchor (draw 14; the Ram's +309 px clearance holds, same 150 / 600 radii). No deviation from the plan. `test_sector_hub_patrol.gd` gains the clearance, eight-anchor, seed, frame-0 IDLE, rocket-in-`EnemyContainer` (8x) and support-wards-Ram rows; its `_spawn_hub` takes `engage_new` to set `start_engaged` on each ship as it enters the container (the brain reads it in `_start()`).
- **t17 as built (level 1 placement).** Five new lines in `level_1_director.gd`, each added inside an existing wave of a DURATION section (no new wave, so no other wave's effective trigger moves): corvettes at deep_space 11.0 + 1.0 s and planet_approach 39.0 + 1.0 / 84.0 + 1.0 s (offset (0, -400)); supports with deep_space's 26.0 s ram at (-255, -460) and planet_approach's 28.0 s ram at (0, -460). **Deviations:** (1) the plan's "65.7 s planet_approach peak" predates the Ph4 t22 ram levers; the measured peak is 6 at 75.5 s before placement and 7 at 98.0 s after, so the extra-corvette boundary inserts at the measured `_peak()["at"]` and asserts the count is 7 (7 + 1 > 7.5). (2) "120 px behind the ram" is read as 120 world px = 60 design units, so the support spawns at world y -920, 116 px outside the 1608 px projectile world rect; harmless (only DISENGAGE frees an AI enemy; it reaches its ram in ~3 s), do not "fix" it. Lives for the count gate: corvette `7.0 + 1.14 + 2 ticks + 8.72 s`, support `9.0 + 4.58 s`, exits over `corridor_starts()` at `[max_speed, 10]` (a 2 px/s speed gave the same worst). `SpecialistExitProbe.worst_disengage()` / `disengage_seconds()` gained an optional trailing `prepare: Callable` run on each instance before `add_child` (the corvette probe zeroes its pools). New test helper `tests/helpers/level1_slice_replay.gd`: replays one window of a section through a real `WaveManager`, stops on a condition, and settles every triggered spawn timer before freeing the world.

### Deliberately deferred
| Item | Deferred to | Reason |
|---|---|---|
| Rocket warning audio | Ph17 | No enemy SFX pipeline |
| Flare / decoy reaction | when a player countermeasure exists | No consumer; rockets would retarget through their aim-point function |
| Hijack Pulse | Ph9 | Scope |
| Shipped module shields, fortress shield nodes | Ph10 / Ph11 | `EnemyShield` + the hook are built; module kind fixture-proven; the bubble ships only as the support's escort bubble |
| Enemy friendly fire from blasts and beams | Ph8 | Only rocket impacts are decided |
| Owner-distance lifetime | Ph13 (if needed) | See above |
| `BulletPool` container injection | Ph10 | First nested launcher |
| Corvette / Support in `ENEMIES_CLEARED` sections, station reinforcements, level 2 | Ph15 | Deadline risk; rails |
| Encounter compositions (Corvette + Fighter, heavy patrol, Carrier + Support) | Ph13 / Ph14 | Made possible here |
| Difficulty levers (`lead_max`, `turn_rate`, `guidance_seconds`, `salvo_period_*`, `repair_fraction`, `shield_capacity`) | Ph16 | |
| A `StateLight` cyan state | Ph17 (if wanted) | The support's state is its projector and tether |

## Phase 5 - as built (2026-10-19)

Plan `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` (Revision 2); narrative in `docs/epics-done/cmufs7elw001pnm2xr3b6fteb/REPORT.md`.
18 tasks (t1-t18); each task's "tN as built" entry in the Phase 5 section above is the detailed record and **wins** over the plan wherever
they differ. This section is the index of what shipped, every deviation, and what is left.

### What was built
- **Gate room (t1):** GUT 253.4 s -> 176.9 s by running real-physics rows on the 8x clock and sharing replays; `scripts/gate-time.sh`.
- **Enemy shields (t2):** `EnemyShield` (`global/components/enemy_shield.gd`) on a `HurtBox` absorber slot (`set_absorber` / `clear_absorber` /
  `has_absorber`, `hit_absorbed(hit_box)`, duck type `absorbs_hit`). Directional arc, 360 deg bubble, capacity, regeneration, reboot,
  sustained lifetime; never absorbs while its host is `is_armored()`; a shielded enemy consumes a default bullet.
- **Ally hooks (t3):** `BaseEnemy.repair()` (never flashes), `can_be_repaired()`, `is_ai_driven()`, `ai_mover_max_speed()`, `accept_tow()`;
  `EnemyBrain.accepts_tow()` overridden in the seven earlier brains and `MissileCorvetteBrain`; `SupportShipBrain` keeps the base default (true).
- **View rect (t4):** `ArenaCamera.enemy_view_rect()`, `EnemyWorld.has_view_rect()` / `view_rect()`.
- **Rockets (t5, t6, t9):** `EnemyRocket` + `EnemyRocketScenes` + five scenes (Dumb, Pursuit, Cluster, Delayed Warhead, Submunition), with art.
- **Missile Corvette (t7, t8, t9, t15, t16, t17):** `MissileCorvette` / `Brain` / `Config`, `WaveBuilder.missile_corvette()`; hub at 315 deg on a
  1900 px ring; 3 placements in level 1 (DURATION sections only).
- **Support Ship (t10-t14, t15, t16, t17):** ward choice and retarget, soft anchor with jink and evasion, Assault view clamp, repair pulse,
  projected shield (bubble in the escort), emergency escort tow, folding projector art; hub: shares the Ram Corvette's anchor; 2 placements in level 1.

### Deviations from the plan (every one)
1. **Owner-distance lifetime not built** (S2, planned): handed to Ph13 with `max_distance_from_player`. `BulletPool` container injection deferred
   again (S3) to the first nested launcher (Ph10 Carrier hangars). `DamageReaction` not adopted (S4); P-15 closed.
2. **`launch_velocity()` on a rail is observed per physics tick**, not in `_process` (t7; the plan's wording was wrong on the 8x clock).
3. **The shoot-down also ignores `CONTACT`-type HitBoxes** (t5), so an ally's ram box cannot defuse a rocket; the ally takes the blast instead.
   **`expired` goes out two physics ticks after a detonation or shoot-down** (t5) because a re-parenting pool re-triggered `area_entered`.
4. **`break_contact` inside an orbit uses side `-orbit_dir`** (t8), not the plan's `+orbit_dir`; any later brain that blends the two needs the same sign.
   `choose_kind()` takes a required third argument (radial speed).
5. **`body_color` export removed** from `EnemyRocket` and its scenes (t9); Pursuit shares `enemy_rocket.png` with Dumb, told apart by a violet
   `modulate`; sprite sizes follow the generator's proportions, not the plan's exact numbers.
6. **A shield does not cover an `ArmorPlate`** (t2): the plate resolves its own hit. Ph10 module shields must sit on a plain part's `HurtBox`.
   At `shield_capacity` 40 one Standard shot (50) breaks a projected shield, then 4 s of reboot; tune knowingly in Ph16.
7. **The Support Ship's tow is a nudge on the ward's own mover** (`accept_tow`), refused by the ward's own brain in committed phases; a refused
   tow is ignored and the support only interposes (t13).
8. **Level 1 (t17):** the plan's "65.7 s planet_approach peak" predated the Ph4 ram levers; the measured peak is 7 at 98.0 s after placement. The
   support spawns 116 px outside the projectile world rect (the "120 px behind the ram" reading); harmless, do not "fix" it. The Missile Corvette
   and the Support Ship are kept out of `ENEMIES_CLEARED` sections by a gate row.
9. **Gate time:** t17 was +15.8 s on the full suite against a 15.0 s allotment, but +12.2 s on the four affected files (`test_fighter_squad.gd`
   varies 63-66 s between runs). Reports for t3, t4, t7 and t10-t13 did not record a clean before / after pair; the table is in `tests/README.md`.
10. **Warning audio, flare / decoy reaction, Hijack Pulse** were out of scope as planned (S7, S8, S10); the telegraph is visual.

### Gaps left for later phases
- **Never play-tested by a human.** Headless tests cannot say whether the 0.7 s salvo telegraph is fair at Assault speed, whether a Pursuit rocket
  can be out-turned by feel, whether the cyan arc and tether read at a glance, whether the projector unfold is visible in motion, or whether the
  hub corvette and the level 1 placements feel crowded. Every number was chosen by arithmetic and a seeded hand-tick.
- **Local-module shield has no shipped consumer** (fixture-proven; Ph10). **Fortress shield nodes** are Ph11.
- **Friendly fire from blasts and beams is undecided** (Ph8); only rocket impacts hurt enemies. The Delayed Warhead's proximity trigger sees allies too.
- **No rocket audio and no decoy** (Ph17); a countermeasure would retarget rockets through `EnemyRocket`'s aim-point function.
- **Support Ship has no state light**; its state is the projector and the tether. The Corvette and Support are absent from `level_2_waves.gd`
  and the station's reinforcements (Ph15).
- **Encounter composition** (Corvette + Fighter, Carrier + Support) is mechanically possible but unauthored (Ph13 / Ph14).
- **Difficulty levers** for Ph16: `EnemyRocket.lead_max`, `turn_rate`, `guidance_seconds`, the corvette's `salvo_period_*`, the support's
  `repair_fraction` / `shield_capacity`.
- **Gate time is near its comfortable limit** (about 200 s of 240 s). Phase 6 must watch its allotments; `test_fighter_squad.gd` alone is ~63 s.

## Phase 6 - Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields (2026-10-20)

Plan: `docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md` (revision 2, answering the round-1 review in `4-review.md`), with
research in `1-context.md` and `2-research.md` (scope check S1–S14) in the same directory. These are *planned* decisions;
check this phase's *as built* section, once written, before relying on them.

### Changes to earlier decisions
- **Collision bit 12 (`area_control`, reserved by the Ph1 roadmap) is not allocated.** Hazard fields are *sampled* by the
  bodies they act on (a registry query), not detected by `Area2D` overlap, so no physics layer is needed. Ph1's rule "no
  layer until something uses it" stands; a later phase that needs an overlap-detected area-control body allocates it then.
- **Context steering is adopted, as a stage inside `EnemyMover`** — the Ph1-named upgrade path — not as weighted blending in
  the brains and not as repulsion nudges. Ph1's rejection of weighted behaviour blending stays in force; brains still make
  one request per tick.
- **The §11.4 Gravity Field moves here from Ph7** (as a gravity-bomb after-effect). Ph7 keeps mines and the Mine Layer.
- **`EnemyBullet` rounds stop on wrecks** (two-sided cover): their HitBox mask gains 1024, and a hit on bit 1024 expires the
  round only when the area's owner answers duck-typed `stops_enemy_rounds() == true`. Asteroids do not answer it, so round
  behaviour against asteroids is unchanged. Any later structure that must stop enemy rounds answers the same method.
- **One slice of Ph5's friendly-fire question is decided here: environmental blasts hurt both sides.** An explosive wreck's
  blast (and hull stress, and a reactor field) damages the player and every enemy by centre distance. Enemy *weapon* blasts
  (rockets) keep their Ph5 rules; the rest of the friendly-fire question stays with Ph8.
- **Brains read `EnemyMover.own_velocity()`, not `actor.velocity`, for "am I settled / stopped" gates** (Ram LINE_UP crawl,
  Sniper SETTLE, Fighter `is_settled` / `is_braking_onto_station` / RUN_IN standing start, Razor feint stop). Inside a
  field `actor.velocity` includes the hazard drift. Heading and lead reads keep `actor.velocity`. Any later brain gate that
  asks "has this ship stopped" must use `own_velocity()`.

### Names and places later phases build on
- **`global/hazards/`**: `HazardInfo` (`RefCounted`, one instance per hazard updated in place; fields `position`, `radius`,
  `pull_force`, `damage_per_second`, `movement_penalty`, `disables_abilities`, `line_of_sight_blocker`, `kind`,
  `core_radius`, `damage_radius`, signed `tangential_force` (+ = clockwise; no `clockwise` export), `avoid_weight`,
  `velocity`, `source`, `claimer_id`; methods `falloff(r)`, `accel_at(pos)`, `penalty_at(pos)`, `contains(pos, margin)`,
  and **claims** `try_claim(node)` / `release(node)` / `is_claimed_by(node)` / `is_claimed()`, stored as an instance id so a
  freed claimer frees the claim), `Hazards` (static registry: `register` / `unregister` / `count()` O(1) /
  `around(pos, reach)` / `accel_at(pos)` / `penalty_at(pos)` strongest-only capped at `MAX_PENALTY` 0.5 /
  `container(tree)` / `hurt_box_of(ship)` / `pulse_damage(tree, at, radius, damage)`), `HazardField` (the one `Node2D`
  script behind the well, anomaly, Gravity Field and reactor field: exports for radius, core, pull, swirl, penalty, stress,
  `duration`, a TELEGRAPH → ACTIVE → QUIET cycle; signals `phase_changed(phase: int)`, `stressed(count: int)`),
  `HazardDrift` (pull integrator, `half_life` 0.35 s, `step(accel, resistance, delta)`).
- **A hazard is any node answering duck-typed `hazard_info() -> HazardInfo`** that registers in `_enter_tree()` and
  unregisters in `_exit_tree()`. Ph7 mines (`kind = &"mine"`), Ph8 laser walls (`&"laser_wall"`) and Ph9 jammers
  (`&"jammer"`, the first consumer of `disables_abilities`) join the same registry with no change to the AI.
- **A hazard never writes a ship's velocity, position or rotation.** Enemies: `EnemyMover` step order is desired → slow →
  context avoidance (skipped while boosting) → accel limit on `own_velocity()` → `+ drift` only when non-zero (applies while
  boosting) → corridor `constraint.filter()` **last** → write; facing from `v − drift`. Players: the Open Space ship adds the
  accel to its own `velocity` before its boost ceiling; the Assault fighter applies a `HazardDrift` **and clamps inside its
  own `_physics_process`** (its states run from `_process`), and `dash_state` gained the clamp. `PlayerBase.hazard_speed_factor()`
  is the player-side slow. The only direct damage path is `Hazards.pulse_damage` (centre distance, a
  `HurtBox.received_damage.emit(n)`; bypasses `EnemyShield`; a plated Ram deflects it).
- **Per-enemy hazard profile = three flat `ShipConfig` fields** (`@export_group("Hazards")`): `hazard_avoidance` 0..1
  (a danger threshold in the context stage), `hazard_margin` px (the skim knob), `hazard_resistance` 0..1 (scales pull and
  slow). Copied onto the mover by `BaseEnemy._ready()`. **A committed attack is `mover.boost()` and ignores avoidance**;
  there is no separate "ignore hazards" API — later committed runs (Ph8 twin-laser sweep, Ph12 Dreadnought ram) use boost.
- **The avoidance stage skips a line-of-sight-blocking hazard claimed by its own actor** (the ship's cover is its
  destination). Any later behaviour that parks a ship beside a structure claims it first.
- **Pass-through rule:** with no hazard in reach and zero drift, enemy velocity and rotation are bit-identical to Ph5
  (the −0.0 case included: a zero drift is never added); `Hazards.count() == 0` costs one compare per step. Later phases
  must keep the pass-through rows green.
- **Runtime hazards are spawned deferred.** A kill or plate break happens inside a bullet's or rocket's `area_entered`
  flush, where Godot refuses a synchronous physics-body add, so every spawned hazard (`HazardField`, `Wreck`,
  `DebrisFragment`) has `spawn_into(container, at, rot)`, which stores the transform and calls `_attach.call_deferred` on
  itself (the `ContactBlast` pattern). Later runtime hazards (Ph7 mines dropped on death, Ph19 wrecks) use the same entry.
- **Runtime hazards live in the node in group `hazard_container`** (`HazardContainer` in level 1 and the hub). No container
  → nothing spawns and no rng is drawn — this is why every level-1 replay and gate is unchanged. Never in the enemy
  container (it holds `ENEMIES_CLEARED` open), never in group `enemies`, never scored. Ph13's `EncounterDirector` should
  own a `HazardContainer` per encounter. The one gate that runs live level 1 with wrecks is
  `test_level1_fighter_exit.gd::test_cloud_descent_clears_in_time_with_wrecks_left_behind`; its pre-approved levers are
  Assault wreck `avoid_weight` 0.3, then halving Assault `wreck_chance` — never raising `enemies_cleared_timeout`.
- **Wreck family** (`assault/scenes/hazards/wreck/`): `Wreck` (`CharacterBody2D` on layer 1, `HurtBox` + `Health`,
  contact box on 1024 armed 0.6 s after entering the tree, `blocks_line_of_sight()`, `stops_enemy_rounds()`, claims
  delegated to its `HazardInfo`, Assault drift 60 px/s down with a 30 s cap, Open Space `lifetime` 40 s, `retire()` fades
  before freeing), `DebrisFragment` (`Area2D`, contact only, not a LOS blocker, optional `source` it never hits),
  `WreckScenes.scene_for(size, explosive)`. **Only a moving wreck or fragment hurts on contact**; placed derelict
  structures are `Wreck` scenes with `lifetime` 0 and are solid but harmless. `ShipConfig` gains `wreck_chance`,
  `wreck_size`, `explosive_wreck_chance`; rolls use the brain's seeded `rng`; alive caps Open Space 8, Assault 4, enforced on
  entering the container, oldest retired. A wreck blocks the player's beam and cannot be cut by it. Ph19's capital wrecks
  reuse `Wreck` / `WreckScenes`.
- **`EnemyBrain.can_see_player() -> bool`** wraps `TargetInfo.line_of_sight` toward the player; wrecks are the first shipped
  blockers. The Missile Corvette still fires past a wreck (§28).
- **Hazards as tools.** Sniper: far-side cover candidates, a `w_cover` score bonus, cover-only re-pick hysteresis, one
  sniper per wreck. Fighter: a new **`COVER` phase appended to its `enum Phase`**, before APPROACH, for solo fighters and a
  squad's LEAD only; `_derive_pass()` and the squad hold are untouched (the pass is derived from wherever the fighter leaves
  cover). Ram: a **well station** `S = P + (P − W)^ · 300` in APPROACH in both modes (clamped to the corridor in Assault and
  refused when the clamped S misses a 30° cone), one Ram per well via the well's claim; with no well `_choose_side()` and its
  rng draw are untouched.
- **Projectiles opt in to fields** by answering `hazard_pull_scale()` and turning their heading (never their speed):
  enemy rockets, gravity / pursuit bombs, player homing and warhead missiles. Bullets, rounds, mines and beams fly true, so
  every lifetime and distance cap still holds.
- **Gate time:** this phase's allowances total ≈ 35.5 s against ≈ 40 s of headroom (GUT ≤ 240 s), so the phase ends near
  236 s. **Ph7 must start by recovering gate time** by the `tests/README.md` rules before adding rows.

### Deferred
- Mines (Ph7); laser barriers / walls (Ph8); jammers, EMP zones and any `disables_abilities` consumer (Ph9); capital-ship and
  boss wrecks, "modules remain as wreckage" (Ph19); carrier escort and hacker positioning tactics (Ph10/18, Ph9).
- Cover for squad wingmen (FLANK / REAR) and squad-coordinated use of cover (Ph14, squad communication).
- Hazards acting on rail-driven spawns (Ph15), the legacy Gunship (Ph10) and the station (immovable).
- Placed wells / anomalies in Assault levels (Ph15; level 1 only gets what its enemies leave). Encounter composition around
  hazards (Ph13/14). Difficulty scaling of hazard values (Ph16). Hazard audio (Ph17). Friendly fire from enemy weapon
  blasts (Ph8).
- Owner options not built by default: the anomaly's shield / targeting distortions, the Ram's deliberate plate throw
  (Debris Charge ships passive only), a designed gravity slingshot.

### Deviations during the build
- **t4 (context-steering stage), four refinements of plan §2.4, all inside `Steering.context_avoid()`; the signature,
  constants and mover wiring are as planned** (task plan `docs/plans/cmvg30aa90073qs2xrw74hcvg/3-plan.md`):
  (1) the inside case uses the outside formula's own limit (skirt 1, cone half-width 90° + one slot) instead of
  `max(0, cos)`, so every heading within 112.5° of the centre is dangerous and a ship inside always steps outward;
  (2) the `prev_dir` hysteresis is blended into the *interest used to rank slots*, not into the output direction (an
  output blend zig-zagged between the two edges of a well straight ahead), and falls back to the brain's own heading when
  the blend cancels (a reversed request); (3) slots are ranked by the signed cosine, so slots more than 90° off the
  request do not tie; (4) a **clear way** returns `desired` bit-identical: when the slot(s) bracketing `desired` (one slot
  when `desired` lies exactly on it) carry the least danger, nothing is touched. The speed floor
  `CONTEXT_MIN_SPEED_RATIO` 0.35 is as planned.
- **t4: every `mover.boost()` bypasses avoidance, including the Razor's IDLE_BOOST** (0.4 s, ~60 px along its idle
  heading), not only attacks; the plan's rule "committed runs are `boost()`; never a separate ignore-hazards API" makes
  no exception. t17, which places the hub's well, should keep Razor idle orbits clear of a well's radius.
- **t4: a drifting hazard is led only once it is within `Hazards.around()` reach** (queried at the hazard's *current*
  centre, reach `hazard_margin + |desired| · 0.6`). For t15's debris (200 px/s, a 120 px lead at 0.6 s) pad the mover's
  reach by a lead allowance if fragments are seen too late; padding is safe, since an info whose skirt is 0 contributes
  nothing.
- **t4: a Swarm Drone BURST across a well is captured only until it commits again.** With the §2.5 well (pull 520, core
  90, damage radius 150) its next BURST (480 px/s) always carries it out, about 1.2 s later, like the Razor's dash. The
  dual-mode row asserts that: the burst reaches the core, the drone stays inside `damage_radius` until its next boost
  (two 0.5 s stress pulses), and with no well the same burst leaves that radius. It does not assert "still inside 2 s
  later", which no geometry gives with the real brain.
- **t10: wreck build choices later tasks depend on** (task plan `docs/plans/cmvg30aax007rqs2x14trnuf9/3-plan.md`):
  - Every wreck and structure body is **one circle**, so `HazardInfo.radius` is the body radius exactly. The radii are
    small 13, medium 25, large 40, satellite 28, cargo platform 55 and station module 45.
  - `Wreck.spawned` is true only after `spawn_into()`. t11's alive cap counts and retires only those, never a placed
    structure.
  - **The yield:** a drifting wreck stops pushing into a body in groups `player` / `enemies`. It holds once that
    ship's hurtbox has registered the contact box, or once it is `YIELD_DEPTH` 1.5 px deep along the drift. It then
    backs off and waits for a clear next step. Ships it was born on are ignored until they separate.
  - **Debris hurts on touch at any speed.** It has no body to stop the ship first.
  - The Open Space lifetime runs through `ProjectileLifetime.max_time = 0` (inert), not a processing toggle. The wreck
    reads its mode once, in `_enter_tree()`.
  - **Rule: no ship hurtbox is larger than its body.** A still wreck is harmless only because of it. The Sniper's
    hurtbox scale went 1.4505 → 1.44 to equal its body, and `test_wreck.gd` gates the rule for all 9 mover-driven
    enemies and both players.
  - **Cover stops the player's Sniper Shot and takes its full damage.** `Bullet`'s `unlimited_pierce` branch ends on
    a parent answering duck-typed `stops_piercing()`, without zeroing damage.
  - Enemy rounds end on a 1024 area only when its owner answers duck-typed `stops_enemy_rounds()`.
    `enemy_bullet.tscn`'s HitBox mask is now 1152.
  - **Arming switches the contact shape on as well as `monitorable`.** A hazard contact box that arms must enable its
    `CollisionShape2D` (born `disabled`), not only flip `monitorable`. Godot never reports an overlap for an area pair
    it built while the box was unmonitorable, and that pair forms for any hurtbox within the broadphase margin. So a
    wreck armed a few px from a ship never hurt it. `DebrisFragment` does the same, and t12 / t15 should follow it.
- **t11: wrecks from deaths.** No deviation from plan §2.9. Build notes later tasks depend on: the alive cap runs in `Wreck._ready()` (not `_enter_tree`, where the `@onready` hurtbox does not exist yet) and counts only `spawned` wrecks that are not retiring, ordered by a static spawn sequence; `BaseEnemy._maybe_leave_wreck()` checks brain, chance > 0 and container *before* the rng draw, so seeded level-1 gates (which have no `HazardContainer`) are unchanged. Explosive wrecks (t12) go through `WreckScenes.scene_for(size, true)` at the same call site. Enemy explosion effects land in the enemy container as before; wrecks never do.
- **t15: Ram plate fragments.** No deviation from plan §2.13. `ram_fragment.tscn` is a `DebrisFragment` (speed 200, deceleration 120, spin 6, life 3.0, contact 12) with no sprite texture of its own: `RamCorvette._throw_fragment()` copies the broken plate's texture and `flip_h`. `DebrisFragment.contact_radius()` now reads its shape by path so it answers before `_ready()` (the Ram sizes `source_clear_radius` on a fresh instance). The fragment is never in group `enemies`, so it cannot hold a level open.
- **t12: explosive wrecks and reactor fields.** No deviation from plan §2.10. Build notes later tasks depend on: `wreck_explosive.tscn` is ONE scene for every size (`WreckScenes.scene_for(size, true)` returns it whatever `size` is; only an unknown size returns null); it is a `Wreck` with `explosive = true`, `fuse` 1.0, `blast_radius` 110, `blast_damage` 25, `reactor_field_scene` (an export), body r 25, HP 20, a `StateLight` held at CHARGING and a `Glow` `AnimatedSprite2D` whose `fuse` animation plays during the fuse. The touch fuse is **polled** (`Wreck._ship_touching()` asks `_registered(ship)` for every ship in groups `player` / `enemies` each tick once armed) and only starts on a hurtbox overlapping the armed contact box, so a stationary explosive wreck that a ship merely bumps (hurtbox never reaches the box) does NOT fuse; a drifting one or a ship that overlaps it does. `_detonate()` is idempotent (`_detonated`) and runs from HP 0 (`destroyed` is emitted first, as for an inert wreck) or the fuse; it emits the new `detonated(world_position)` signal. `ShipConfig.explosive_wreck_chance` (Bomber 0.5, Missile Corvette 0.5, every other config 0) is drawn from the brain's rng only when it is above 0 and only after a successful wreck roll, so every config with 0 keeps its draw order. The reactor field is `reactor_field/reactor_field.tscn` (`ReactorField`, a `HazardField`; ring + burn sprite + 0.5 s fade).
- **t13: Sniper cover.** Plan §2.11 as written, plus four refinements that later tasks (the Fighter's COVER in t14) can reuse:
  (1) a **plain** candidate inside a line-of-sight blocker's body (`radius + BODY_MARGIN` 20 px) is rejected like a point
  in a well, since a ray starting inside a body is not blocked and the ship could not reach it; (2) a cover candidate is
  pushed **one more peek step** (30 px) past the first clear point when a ray can be spared, because the muzzle sits 45 px
  from the hull and a point that only just clears the wreck's edge loses the line mid-turn; (3) the peeks may spend at
  most `max_los_rays − 2` rays, leaving two for the plain candidates; (4) **SETTLE waits for the nose to come round**
  (`TURN_DONE` 0.1 rad, inside `SETTLE_CAP`) before it calls a blocked line a refusal, **only while it holds a claimed
  cover wreck**, so a sniper that reaches its cover point mid-turn is not sent away; with no claim SETTLE is as before.
  The claim is taken in `_set_target_point()` (the choice itself skips a wreck another ship holds) and released on
  BREAK_CONTACT, DISENGAGE and `on_suspended()`; `SniperBrain.claimed_cover` is the held `HazardInfo`. A hold-through-
  AIM row runs on real physics (8× clock) as well as hand-ticked, because the hand-ticked harness overwrites the
  position after `move_and_slide` and so never feels the wreck's body. New `SniperConfig` fields: `cover_search_radius`
  700, `cover_gap` 50, `cover_radius` 140, `w_cover` 1.0, `cover_hysteresis` 0.15.
- **t14: the Fighter's COVER phase.** Task plan `docs/plans/cmvg30aba0087qs2xwv86aq35/3-plan.md` (Revisions 1 and 2).
  `FighterBrain.Phase.COVER` is appended (value 9). Brain state `cover: HazardInfo` (the claimed wreck) and
  `cover_point`. The pass machinery (`_derive_pass()`, the RUN_IN latch, the squad hold) is untouched;
  `_derive_pass()` is only *called* from COVER and from the entry check.
  Deviations from §2.12:
  1. **Seven** flat `FighterConfig` fields (Cover group), not six: `cover_min_budget` is **5.0** (6.0 can never open,
     because `budget.update()` runs before the first APPROACH tick, leaving `6.0 − 1/60`). The new
     `cover_pass_reserve` 3.0 is used trip-aware: COVER ends in Assault once
     `remaining() <= cover_pass_reserve + |X − S| / max_speed`.
  2. Four more entry rules:
     - the wreck is nearer the player than the fighter ("on its way in"), or a hub fighter would fly away from the
       player to hide and lose it;
     - in Assault, C lies inside the corridor shrunk by the hull;
     - **the swoop rule** (`_swoops_from`, Revision 2, found while building): a solo hides only where it breaches out
       of cover (C inside APPROACH's breach radius less 30 px), and a squad LEAD only where its S is within
       `2 × plan radius − 30` of C. From anywhere else APPROACH plans a Dubins lead-in from rest with the wreck in the
       way; the wreck's skirt bends the fighter off that path, and the re-plan from near S loops. Measured over 270
       layouts: 84/144 Open Space and 81/126 Assault post-cover approaches were 3–6 s late, most Assault ones never
       attacking. With the rule: 0 of 216 solo and 0 of 112 LEAD covers in Open Space. In Assault, 2 of 184, both
       fighters starting below the corridor floor, which no level does, and both still attacked;
     - in Assault a centred player's S is clamped inward, so the solo band is only 300–325 px.
  3. Extra exits: no player, and no longer the squad's LEAD.
  4. `_enter_calm()` (IDLE / RETURNING) also clears `_cover_used`, so a hub fighter takes cover once per engagement.
  5. N8 is accepted: a LEAD in cover leaves its FLANKs to go alone after `flank_wait_max`.

  Consequences:
  - Level-1 fighters practically never take cover: the check runs on the spawn tick, spawns are outside the corridor,
    and the Assault swoop band is narrow. The wreck-guard replay counts COVER entries in its print and saw 0 in three
    runs. Checking at corridor entry instead would make Assault cover common; it is left as an owner option.
  - A future encounter that wants Assault cover needs a player off-centre or a wider corridor.
- **t16 (Ram well station):** the 4.0 s give-up is `well_setup_max` plus the trip to the station at claim time (`RamCorvetteBrain.well_setup_limit`), not a flat 4.0 s: plan §2.14's own bearing-0 row (a Ram 900 px out beyond the well, 1200 px from `S`) cannot arrive in 4 s at 280 px/s. A corridor-clamped `S` closer than `well_station_tolerance` to the player is also refused (a player on the corridor's x edge collapses `S` onto itself, and a zero-length line passes any cone). New brain fields `well_ticket`, `well_station`, `well_refused`; with the shipped `engage_seconds` 4.0 the Assault gate (`remaining >= well_setup_max + line_up_cap`) never opens, so the station is Open Space-only until an Assault encounter gives a well-fighting Ram a longer budget.
- **t18 (hub tactical space):** `sector_hub.tscn` `TacticalSpace` at well (2956, 1225), anomaly (3656, 1225), structures 500 px hub-side, three still debris pieces; the `Background` ColorRect's right edge is now 4400 (was 1720) so the space is not on the bare clear colour. Later phases that place hub content past x = 1720 need no further change.

## Phase 6 - as built (2026-10-21)

Report: `docs/epics-done/cmug23om70001m52wqfwclf3l/REPORT.md`. Where this section and the planned section above differ, this one wins.
The planned section's "Deviations during the build" list above is the per-task record; this is its index.

### What was built
- `global/hazards/` (`HazardInfo`, `Hazards`, `HazardField`, `HazardDrift`); the hazard profile on `ShipConfig` and the drift / slow /
  context-avoidance stage in `EnemyMover`; pull and slow on both players.
- Hazards in `assault/scenes/hazards/`: `gravity_well/`, `energy_anomaly/`, `gravity_field/`, `reactor_field/`, `wreck/` (`Wreck`,
  `DebrisFragment`, `WreckScenes`, derelict structures, drifting debris, the Ram plate fragment), each with a `HAZARD.md`.
- Wrecks left by deaths in both modes through the `HazardContainer`; explosive wrecks and reactor fields; Gravity Field from gravity bombs;
  rockets, bombs and player missiles bend in fields.
- Tactics: Sniper far-side cover, Fighter `COVER` phase (solo / LEAD), Ram well station; `EnemyBrain.can_see_player()`.
- The hub's `TacticalSpace` (well, anomaly, derelict cover, still debris).
- Final gate: GUT 216.3 s, 2139 tests, all passing.

### Deviations from the plan (every one)
All are recorded in detail in "Deviations during the build" above; in short:
1. Context-steering refinements inside `Steering.context_avoid()` (t4): inside-case limit, hysteresis on slot ranking, signed-cosine
   ranking, a clear way returns `desired` bit-identical.
2. Every `mover.boost()` bypasses avoidance, the Razor's idle boost included (t4).
3. Wreck build choices (t10): one circle per body, the yield rule, debris hurts at any speed, no hurtbox larger than its body (the
   Sniper's hurtbox scale 1.4505 -> 1.44), cover takes the Sniper Shot's full damage, `enemy_bullet.tscn` mask 1152, and arming a
   contact box enables its shape.
4. Sniper cover (t13): four refinements (plain candidates rejected inside a wreck body, one more peek step, peeks spend at most
   `max_los_rays - 2`, SETTLE waits for the nose while a claimed wreck is held).
5. Fighter COVER (t14): seven config fields, not six (`cover_min_budget` 5.0, new `cover_pass_reserve` 3.0), four extra entry rules including
   the **swoop rule**, extra exits, `_enter_calm()` clears `_cover_used`. Level-1 fighters practically never take cover.
6. Ram well station (t16): the give-up is `well_setup_max` plus the trip, not a flat 4.0 s; short clamped stations are refused; the Assault
   station never fires with the shipped `engage_seconds` 4.0.
7. Hub (t18): the `Background` rect's right edge moved from 1720 to 4400.
8. No deviation from the plan in t1-t3, t5-t9, t11, t12, t15, t17 (t11, t12, t15 note build details only).

### Gaps left for later phases
- Nothing has been play-tested by a human; every hazard, avoidance and wreck number is a starting value pinned by tests.
- Level 1 fighters almost never take cover (check at spawn tick); checking at corridor entry is an owner option. Wingman and
  squad-coordinated cover belong to Ph14.
- No Assault Ram can use a well station until an encounter gives it a longer budget; Assault levels have no placed hazards (Ph15).
- `disables_abilities` has no producer (Ph9 jammers); mines (Ph7); laser walls (Ph8); capital / boss wrecks (Ph19); hazard audio (Ph17);
  the anomaly's shield / targeting variants and a deliberate plate throw remain owner options.
- Fighter cover legality is checked at entry only (documented, bounded).
- **Gate time is 216 s of 240 s: Ph7 must start by recovering time** (`tests/README.md` rules), logging it here.

## Phase 7 - Enemy rework, phase 7: mines, minefields and the Mine Layer (2026-10-23)

Plan: `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` (Revision 4, answering plan review rounds 1–3 and the owner's "Fix those issues in your plan"). The research stage left no
`1-context.md` / `2-research.md`, so the plan's §1.1 *Scope check* (S1–S11) is this phase's re-validation against the code, and §2.18
gives every number's origin (an earlier phase, a measurement, a derivation, or a *starting value* = judgement, not play-tested). These
are *planned* decisions; check this phase's *as built* section, once written, before relying on them.

### Changes to earlier decisions
- **Pooled hazards register on `launch()`, not in `_enter_tree()`** (Ph6's rule). A pooled mine sits idle in the tree inside its `BulletPool`,
  so it registers when a life starts and unregisters in `_mark_done()` and `_exit_tree()`. Any later *pooled* hazard follows the same rule.
- **`EnemyOrdnance`'s MINE logic moves to a subclass**, `EnemyMine`, and the Bomber's `mine.tscn` becomes the PROXIMITY variant (same path;
  it has no UID). The bomb paths stay in `EnemyOrdnance`, byte-identical, behind three virtual hooks (`_move_mine`, `_trigger_seen`,
  `_on_detonated`) and an overridable `_reset_props()`.
- **`mine.tscn`'s authored `warning_time` changes 0.5 → 0.25**, the value `Bomber.drop()` already applies on every drop, so the scene itself
  passes the warning rule. No behaviour changes.
- **`mine_life` 0 now means "never fizzles"**. The Bomber always sets 8.0, so it is unaffected. The `ProjectileLifetime` `max_time` is the
  backstop (0 = inert).
- **Bomber mines become hazards** that other enemies (the Bomber included) avoid. Pre-approved levers, in order, if **any existing row** (a level-1
  gate, `test_bomber.gd`, `test_enemy_ordnance.gd`) turns red because of it, on `mine.tscn` only: `hazard_pad = 0`, then `registers_hazard = false`.
  No gate bound or assertion moves.
- **Friendly fire, one more slice decided:** *placed* mines (`hostility = ALL`) are set off by, and blast, both sides through
  `Hazards.pulse_damage` (Ph6's environmental rule). Every mine an enemy lays (`hostility = PLAYER`) keeps Ph4's rules: player
  hurtboxes only, `ContactBlast`. The rest of the blast/beam friendly-fire question stays with Ph8.
- **Mine Layer departures from the Ph4 wall rule** (Ph4 t10): the arrival time T comes from **the Bomber's earliest-feasible scan**
  (`BomberBrain._solve_arrival`: 0.1 s steps up to a 6.0 s cap, then 5 bisections), with `t_lead(T) = T + run_in / lay_speed + min(c, lead_horizon 3.0)`
  (only `c` capped, as in Ph4) and a feasibility test `|R − pos| / max_speed + (max_speed − v0)² / (2·acceleration·max_speed) ≤ T` (a spin-up term for the
  layer's current speed). Revision 3's self-referencing `t_lead` diverged against a moving player, as Ph4's fixed-point iteration did and the drop fires after the rest point is passed by the eject lead (the Bomber's "plus"), but the layer places the
  pass centre `ahead_distance` 260 px ahead along the player's frame (a distance) instead of adding `wall_margin + (trigger + arc) / |v|` to
  `c` (a time), and it freezes the plan within `commit_distance` 200 of the line's **run-in point** R (150 px before the start S).
- **The race-track mine (`assault/scenes/race/track/mine.gd`) is not reconciled** with the family (deferred to Ph7 by Ph4). Racers are
  outside the rework, so it stays a race prop.
- **Already delivered, not rebuilt:** the §16 explosive collision profile (Ph1 assigned it to Ph7; it is `ContactProfile.Mode.EXPLOSIVE`,
  built in Ph2) and the §11.4 Gravity Field (Ph6).

### Names and places later phases build on
- **`EnemyMine extends EnemyOrdnance`** (`assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`).
  - `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }` (append-only) and `enum Hostility { PLAYER, ALL }`.
  - Methods: `retire()` (fizzle, no blast, `expired`), `chain_trigger(delay)`, `hazard_info()`, `link_points()` (CHAIN fuse links).
  - Exports: `variant`, `hostility`, `hazard_pad` (60), `registers_hazard`, `placed`, `shot_detonates` (CHAIN), plus each variant's own
    (`drift_speed` / `drift_direction` / `drift_leash`, `notice_radius` / `home_speed` / `home_lose_radius` / `home_max_distance`,
    `chain_radius` / `chain_delay`, `pulse_radius` / `disrupt_strength` / `disrupt_seconds`, `emp_radius` / `emp_seconds`).
  - Contract unchanged: `expired` once per life, `reset()`, `launch(dir, speed, target_point)`. A pooled mine never frees itself. A mine
    is never in group `enemies` and never scored.
  - Scenes `mines/<variant>_mine.tscn`; PROXIMITY = `enemy_ordnance/mine.tscn`. `EnemyMineScenes.scene_for()` / `pool_size_for()` /
    `export_of()` (reads scene exports through `PackedScene.get_state()`, so gates never type numbers).
  - **Variant tuning (trigger, warning, blast, effect) lives in each mine scene** (the Ph5 rocket rule). The Mine Layer's `drop_mine`
    overrides only `arm_delay`, `eject_time` and the life; the Bomber's `drop()` keeps its Ph4 overrides for PROXIMITY only.
- **Mine hazard footprint (measured with `Steering.context_avoid`):** `HazardInfo.kind = &"mine"`, `radius = trigger_radius + hazard_pad`
  (80 + 60), `avoid_weight` 1.0 for every mine, `velocity` for moving mines, no pull / slow / LOS block. At this footprint a ship with
  `hazard_avoidance` ≥ 0.8 keeps ≥ 145 px from a mine centre; 0.6–0.7 (Bomber, Missile Corvette) skirts at ≈ 90–110 px; the 0.5 Ram grazes.
  A smaller pad or weight lets a 0.6 ship cut inside the 80 px trigger. Mines do not bend in fields (`hazard_pull_scale()` 0).
- **Placed mines:** `placed = true` makes a mine self-owned (`expired -> queue_free`, backstop inert, and **`mine_life = placed_life` always**, a new
  export defaulting to 0 = never fizzles, so the 8.0 s `mine.tscn` authors for the Bomber never reaches a placed PROXIMITY mine) and
  launches it, so a lone mine dropped in any scene arms, registers and triggers. **The setup is a deferred `_start_if_placed()` queued by every
  mine's `_ready()`**, and the `ProximityArea` mask is set from `hostility` in `launch()`, because Godot readies children before their parent:
  a `Minefield` sets `placed`/`hostility` on editor-placed children in its own `_ready()`. Any later parent that configures mines relies on this.
- **ALL-hostility trigger filter:** a layer-128 area, or a layer-512 area whose `get_parent()` is in group `enemies`. `BaseEnemy` does not
  join `enemies`; every shipped enemy's own `_ready()` does, and any new enemy must too.
- **Warning rule for every mine scene:** `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`; `effect_radius` is
  `blast_radius` when `blast_damage > 0`, else `emp_radius`; `own_speed` is `home_speed` / `drift_speed`, else 0. Asserted from exports.
- **Chain:** a CHAIN detonation calls `chain_trigger(chain_delay 0.2)` on every live mine whose centre is within `chain_radius` 150 (via
  `Hazards.around`, kind `&"mine"`, then centre distance). Only CHAIN mines propagate. A chained mine skips its warning.
- **Player disruption hooks on `PlayerBase`, implemented by both ships:**
  - `apply_boost_disruption(strength, seconds)`, `boost_efficiency() -> float`, `signal boost_disruption_changed(efficiency: float)`.
    Strongest and longest win, never stacked. `MIN_BOOST_EFFICIENCY` 0.15. `_step_disruption(delta)` runs from each ship's physics tick.
  - **Efficiency is checked before anything is spent:** in `OpenSpacePlayerShip._step_boost()` before `try_spend_tank()` and in the default
    boost's start condition; `EngineBoostModule.try_activate()` keeps a guard for the Assault H path. A refused press spends no tank.
  - **The excess rule:** a disrupted speed is `floor + (speed − floor) × efficiency`, never a plain product, so a disruption never slows a ship
    below normal flight. Shift boost and Boost Drive floor at the new virtual `PlayerBase.cruise_speed()` (Open Space `max_speed` 420, Assault
    `MoveState.move_speed` 360); the Assault dash floors at `DashState.move_speed` 180. Warp blink distance × efficiency. Below the floor the
    boost, Drive, dash and warp are all refused. Any later speed-affecting debuff (Ph9 EMP, jammers) should use the same rule.
    Cruise thrust, turning and firing are never touched.
- **EMP entry point:** `EmpPulse.emit(tree, at, radius, seconds, source) -> int` (`global/components/emp_pulse.gd`, static) calls duck-typed
  `apply_emp(seconds, source)` on group `player` only.
  - `PlayerBase.apply_emp(seconds, source)`, `is_emp_disrupted()`, `signal emp_changed(active: bool)`.
  - **Ph7's stand-in effect is `apply_boost_disruption(1.0, seconds)`.** Ph9 replaces the effect body and extends `EmpPulse` to enemies and
    seeking weapons, **keeping both signatures**. Ph9's EMP Pulse weapon and its jammers call `EmpPulse.emit`.
- **`Minefield`** (`assault/scenes/hazards/minefield/`, `HAZARD.md`):
  - patterns AUTHORED / RING / GRID / SCATTER, flat variant weights, own seeded rng, `hostility` ALL by default;
  - unpooled self-owned `placed` mines, placed DRIFTING mines ping-pong within `drift_leash` 120 on a seeded direction; a beacon (art
    `minefield_beacon.png`); the field frees itself after its last mine;
  - drifts down at 60 px/s in Assault (the wreck precedent), still in Open Space.
  - A later phase places Assault fields (Ph15) or encounter fields (Ph13) with this scene.
- **Mine Layer** (`assault/scenes/enemies/mine_layer/`): `MineLayer`, `MineLayerBrain`, flat `MineLayerConfig`.
  - `MineLayerBrain.Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only).
  - `MineLayer.drop_mine(variant, rest_point)` is the one configuring call. Per-variant root `BulletPool`s use `persist_after_owner_death`; an
    exhausted pool falls back to PROXIMITY.
  - `set_hatch_open(0..1)`, `MineWake` (self-freeing `Line2D`). `WaveBuilder.MINE_LAYER` / `mine_layer()`. COLLISION contact.
    `hazard_avoidance` 0.8, `hazard_margin` 24.
  - Rail fallback: a PROXIMITY mine every `rail_mine_interval` 1.6 s.
  - `accepts_tow()` false in LAY.
  - **Entering DISENGAGE calls `mover.release_constraint()` and sets `mover.max_speed = exit_speed`** (the Bomber's `_enter_disengage()`), so the Assault
    corridor never holds an exit in and `SpecialistExitProbe` measures the real exit.
  - Test seams later phases may reuse: `plan_pass()`, `freeze_plan()`, `pass_form`, `plan_frozen`, `frame_f`, `arrival_time`, `flight_time()`,
    `spread_fallbacks`, `fence_fallbacks`, `pass_run_in_point`.

### Conventions
- **A pass is a line, not a spray:** one line of 6 mines on a 600 px pass laid *across* the player's path. APPROACH seeks the run-in point
  `R = S − u·run_in` (150 px), hands over to the run-in within `path_lookahead` 60 px of R, follows R → S along the axis at `lay_speed`, and starts LAY
  when its centre's projection on the axis **crosses** S from the R side, so the line is laid sideways whatever direction the layer arrived from.
  - **Two plan forms (Open Space).** *Lead* (a moving player, |v̄| ≥ 60, the layer can get ahead of): the line across the predicted path, from the
    scan above. *Fence* (a standing player, or a moving player with no feasible arrival): `C = P + f·320`, between the player and the layer. Against a
    player cruising faster than ≈ 120–150 px/s the scan finds no arrival, so a cruising player gets a fence line beside or behind them (stated to the owner).
  - **A standing player's frame is latched:** `f` (P toward the layer) and the sign of the axis are fixed at APPROACH start (and on a moving → standing
    switch) until the plan freezes. Re-reading them every tick made R turn with the layer and the plan never froze (plan review round 3).
  - The plan freezes within `commit_distance` 200 of R, or at once for a fence fallback; a frozen plan is never re-planned. A lead plan that turns
    infeasible before the freeze is frozen as it stands. ZIGZAG puts mines on the vertices
  (half-wavelength 100, amplitude ±35: chords 122.1 px at 35.0°); ARC bows toward the player (`arc_depth` 110: chords 100–122.3 px, ≤ 35.1°).
  - Open Space: gap from the end of one LAY to the next ≥ `break_seconds + pass_period_min` = 1.2 + 5.0 s (period 5–7 s), so one line every
    ≈ 10–14 s. Spread: a new centre is ≥ 380 px from every live earlier one. Fence form: C, then C rotated about the player by ±θ, ±2θ with
    `θ = 2·asin(min(1, 390 / (2·|C − P|)))` (the latched frame rotates with it). Lead form: C shifted **along the player's heading** by 0, then 390 px,
    inside the scan (a rotation would move the line off the predicted track). With none legal the plan proceeds (`spread_fallbacks`). (Revision 1's "6–9 s between passes" is superseded.)
  - Open Space backstop: after `approach_max_seconds` 6.0 s without freezing, the fence fallback is taken (frozen at once, `fence_fallbacks` + 1). With
    the latch and the scan it should never fire; rows assert `fence_fallbacks` 0 for a standing player and a 100 px/s player led from ahead.
  - DISENGAGE with no planned pass exits along the current heading (velocity, else facing); that is what `SpecialistExitProbe` measures.
  - Live cap: 18 in Open Space, 8 in Assault; the oldest is `retire()`d.
  - A tail drop (one PROXIMITY mine, ≤ every 2.5 s) punishes a player chasing inside the rear 60° cone within 280 px.
- **Assault:** the pass axis is horizontal, the line is clamped into `view_rect().grow(−174)`, one pass per life. The budget defers to the end of
  LAY (stall guard ≤ 5.67 s). Attack-in-budget rows from every level-1 spawn.
- **Open Space persistence:** laid mines never fizzle (`mine_life` 0, backstop 240 s) and survive the layer's return home and its death.
- **Never in an `ENEMIES_CLEARED` section:** the Mine Layer, or anything whose mines persist. Guard rows sit in `test_engagement_deadline.gd`; the
  spill-over row in `test_level1_specialist_spawns.gd` adds `assault_mine_life` (9 s). The Mine Layer counts as a specialist in the frozen 2.5× gate.
- **Hub:** the Mine Layer is draw 15 (earlier seeds unchanged), anchored on bearing −22.5° of a 2600 px ring (≈ (2402, −995)). A placed RING
  minefield sits at `TacticalSpace` (3300, 560). `test_sector_hub_patrol.gd`'s `_patrol_groups()` includes the layer and `_element_radius()`
  includes `Minefield` as `radius + (drift_leash if w_drifting > 0) + the PROXIMITY scene's trigger_radius` (400 px for the hub field), so the Ph6
  clearance sweep covers both. Any later placed field is covered by the same formula. Radii (perceive / lose): 650 / 1500, sized by two config
  inequalities: the cycle `standoff_range + break_speed·break_seconds + pass_length/2 + run_in` (1362) and the lead form's farthest point against a player
  at ≤ 220 px/s, spread shift included (1415.8). A faster player is deliberately let go.
- **Level 1:** deep_space 16.0 s wave (from the left) and planet_approach 47.0 s wave (from the right), inside existing waves.
- **Gate time:** t1 must free ≥ 12 s first (a hard floor; else `ESCALATE`), using only `tests/README.md`'s rules (8× clock for the measured 1×
  files, shared scenarios, dropping unread bookkeeping); a production speed-up is a last resort. Per-task allotments total 28.5 s (phase ends ≤ 232.9 s). GUT ≤ 240 s.

### Test conventions added
- `tests/helpers/fixture_enemy.tscn`'s `HurtBox` has no shape and the fixture joins no group: a row that needs a mine (or any `Area2D` poll) to see
  it adds a 14 px `CircleShape2D` and `add_to_group("enemies")` at runtime. The shared fixture scene is not edited.

### Deferred
| Item | Deferred to | Reason |
|---|---|---|
| EMP on enemies, the real EMP player effect, jammers, hijack | Ph9 | Keep the `EmpPulse.emit` / `apply_emp` signatures |
| Placed minefields in Assault levels | Ph15 | Ph6 rule for placed Assault hazards; the scene already works in Assault |
| Encounter compositions with a Mine Layer (§19 sniper ambush) | Ph13 / Ph14 | |
| Mine numbers by difficulty (`mines_per_pass`, `max_live_mines`, `pass_period_*`, scene `warning_time`) | Ph16 | |
| Mine and layer audio | Ph17 | |
| A Mine Layer scattering mines on death | owner option | The Ph6 deferred-spawn entry is ready |
| Pulse / EMP mines affecting enemies | Ph9 (if wanted) | Enemy-laid mines never trigger on enemies |

### Built in t1 (gate room)
- GUT `Time` 216.34 -> 202.3-202.5 s (two full `scripts/gate-time.sh` runs; `check-test-leaks.sh` 201.98 s, clean), -13.8 s against the 12 s floor. 2139 tests / 78348 asserts unchanged. Only the `tests/README.md` -> Gate time rules were used; no production code changed.
- 8x clock (`_scale_clock(n)` / `_restore_clock()` + `after_each`): `test_armor_query.gd` (all rows), `test_station_laser_phase.gd`, `test_station_incoming_damage_paths.gd`, `test_swarm_drone.gd` (its real-physics rows). Two rows deliberately do not run at 8x: the laser phase's `0.1 s`-in-a-`0.2 s`-warning row (2x) and `test_station_rotates_only_during_the_laser_phase` (1x: its expected rate is computed from `Engine.physics_ticks_per_second`, which an 8x clock would change).
- **`test_station_assault_section.gd` cannot take the 8x clock**: `LevelDirector`'s ENEMIES_CLEARED poll and settle compare `Time.get_ticks_msec()` (wall clock), so a scaled clock makes the rows' game-time `wait_seconds()` too short for it (the three awaiting rows went red). It stays 1x, 4.1 s. Any later test that awaits a `LevelDirector` wait must stay 1x for the same reason.
- `SpecialistExitProbe.worst_disengage()` is memoised for the GUT process, keyed by (scene path, phase, speeds, cap, start set, `prepare`). Only the Sniper view-grid measurement is actually shared between `test_engagement_deadline.gd` and `test_level1_specialist_spawns.gd` (their Ram speed lists differ), so it saves ~1.3 s. Later phases that probe the same ship with the same inputs get the figure for free; a different input list does not reuse it.

### Built in t2 (the mine family)
- `EnemyMine extends EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`) and `EnemyMineScenes` (`mines/enemy_mine_scenes.gd`) as plan §2.1. `EnemyOrdnance` gained `_reset_props()`, `_move_mine(delta)`, `_trigger_seen()` (was `_player_in_range()`) and `_on_detonated()`; bomb paths unchanged. The MINE fizzle guard is `mine_life > 0.0 and _clock >= mine_life`. `_draw()` skips the body circle when a `Sprite` (`Sprite2D`) child has a texture (none does yet; t9 art).
- `mine.tscn` keeps its path and has no UID: script `enemy_mine.gd`, `variant` PROXIMITY (the default, so not serialised), authored `warning_time` 0.5 -> 0.25. `EnemyMineScenes.scene_for(PROXIMITY) == EnemyOrdnanceScenes.MINE`.
- **Deviation (review r1):** `_start_if_placed()` also sets the `ProjectileLifetime`'s `use_world_rect = false`, not only `max_time = 0`. In Assault the rect is the corridor + 64 px, so a placed mine authored outside it (a Minefield's outer mines entering from above) otherwise expired and freed itself on its first tick. A placed mine therefore has no backstop of any kind; its only ends are blast, defuse, `placed_life` and `retire()`.
- **Additions over §2.1:** `EnemyMine.is_fizzling()`; `retire()` unregisters at once, and a natural fizzle unregisters on the tick it starts (a fading mine cannot trigger, so it is no hazard); `_enter_tree()` re-registers a live launched mine after a `reparent()`. `EnemyMineScenes.export_of(variant, property, fallback, node_path := ^".")` takes an optional child path (e.g. `^"ProjectileLifetime"`); `SceneState` spells child paths `./Child`, which it normalises. `scene_for()` returns null, with no error, for a variant whose scene is not built yet, so sweeps cover "every built variant"; t3/t4/t6/t7 add their scenes there.
- `pool_size_for()` reads the weights `w_proximity` ... `w_emp` duck-typed (`"w_x" in cfg`, missing = 0); the sum covers all six weights.
- Pre-approved levers: **none used.** With Bomber mines registered as hazards, every level-1 gate, every `test_bomber.gd` (36) and `test_enemy_ordnance.gd` (35) row, `test_context_avoidance.gd` and the Ph6 pass-through rows stayed green unchanged.
- Measured: the pure-stage avoidance rows reproduce plan §2.3's table exactly (av 0.6: 90.1 / 99.2 / 109.1 px; av 0.8: 152.9 / 152.5 / 156.2 px). The real mover keeps 154.5 px head-on, against 0.0 px for its control.
- Test convention: a lambda connected to `get_tree().physics_frame` inside a `use_parameters` test stayed connected into the next parameter run despite its `disconnect()`, and touched freed captures there. Per-tick test drivers are a child `_Ticker` node of the scene instead (`test_enemy_mines.gd::_tick_each_frame`), so they are freed with it.
- Gate time: GUT 202.8 -> 203.8 s (`scripts/gate-time.sh`), allotment 3.0 s.

### Built in t5 (boost disruption on both players)
- `PlayerBase` (`global/entities/player_base.gd`): `signal boost_disruption_changed(efficiency: float)`, `MIN_BOOST_EFFICIENCY := 0.15`, `apply_boost_disruption(strength, seconds)`, `boost_efficiency()`, virtual `cruise_speed()` (base 0; `OpenSpacePlayerShip` `max_speed`, `AssaultPlayer` `MovementStateMachine/MoveState.move_speed`, read per call) and `_step_disruption(delta)`, called **first** in both ships' `_physics_process` (ahead of the Assault dialog / knockback / engine-boost returns). The signal fires on start, on a stronger re-apply and at the end (1.0); a longer-only re-apply changes no efficiency and emits nothing. Strength <= 0 or seconds <= 0 is ignored.
- **Addition over §2.6:** `PlayerBase.disrupted_speed(speed, floor_speed) -> float` is the one implementation of the excess rule, and it returns `speed` itself when undisrupted, so every undisrupted speed is bit-identical to Ph6. The Shift boost (`OpenSpacePlayerShip._boost_speed()`), the Boost Drive and the dash call it; t6/t7 and Ph9 should apply disruption only through `apply_boost_disruption()` and read it only through these.
- `EngineBoostModule`: `try_activate()` refuses below the floor (after its own active/cooldown refusal); the burst's `_start_speed` / `_end_speed` are computed once at activation through the player's `disrupted_speed(…, cruise_speed())` (duck-typed; a ship without the hook gets the raw exports) and `tick()` lerps between them. `can_activate()` is unchanged; its comment now names the efficiency guard as the caller's.
- `DashState`: the refusal sits after the timer/key checks and **before** the warp branch, and has the cooldown's shape (`state_transition.emit(transition_state)`), so it refuses both the roll and the warp. Roll speed `actor.disrupted_speed(dash_speed, move_speed)`; warp distance `_WARP_DISTANCE * efficiency`.
- Readability: the ring is a code-built `Line2D` child named `BoostDisruptionRing` (24 points alternating radius 20 / 23 px, violet `Color(0.72, 0.4, 1.0)`, width 1.5), built lazily on the first disruption, flickering and turning on its own `rotation` while active. `BoostBar._on_boost_disruption_changed(efficiency: float)` (connected by `OpenSpacePlayerShip._ready()`) makes `_fill_color()` return `_FILL_COLOR_DISRUPTED` (same violet) in either tier, and its `_process` flickers `modulate.a` from an accumulated clock; `modulate` resets to white at the end.
- Measured rows (all ±1 px/s or tighter): Shift boost 532, Drive 852 → tail 452 (minimum ≥ 420), H-key Drive 816, dash 248, warp 48 px; refused at 0.9 with nothing spent; the floor is inclusive (0.85 boosts, 0.86 refused). No *starting value* changed.
- Gate time: GUT 204.62 -> 203.82 s (`scripts/gate-time.sh`; the new file ≈ 0.5 s, allotment 1.5 s). Nothing awaits, so `check-test-leaks.sh` was not required.

### Built in t3 (drifting and homing mines)
- `EnemyMine` (`mines/enemy_mine.gd`) gained the DRIFTING and HOMING behaviour and 9 exports (`drift_speed` 35, `drift_direction` ZERO, `drift_leash` 0, `drift_max_distance` 1400; `notice_radius` 260, `home_speed` 60, `home_turn_rate` 2.0, `home_lose_radius` 380, `home_max_distance` 900), all in `_reset_props()`. Both write `position` only, through the `_move_mine()` hook, so they need no physics and a moving parent carries them. `HazardInfo.velocity` is refreshed every tick (zero when not moving); PROXIMITY's stays zero.
- Scenes `mines/drifting_mine.tscn` (`variant` 1, `mine_life` 0, backstop 60 s) and `mines/homing_mine.tscn` (`variant` 2, `mine_life` 30, backstop 40 s), both the shared 80 / 0.5 / 0.25 / 48 / 30 / 60 numbers: (80 + 48) / 0.25 = 512 >= 475 / 500. `EnemyMineScenes.scene_for()` returns them. No UIDs hand-typed.
- DRIFTING drifts from the end of the eject (`clock > eject_time`), so "35 x t" counts t from there. A launched mine takes its launch direction; a zero launch direction falls back to `drift_direction`, and a zero `drift_direction` is still (the scene authors ZERO, so a bare placed drifter does not move; fields set a direction). The 1400 px cap clips the last step to exactly 1400 and calls `retire()`. A leash ping-pongs on a signed offset and never fizzles on distance.
- HOMING notices at `<= notice_radius` and keeps the player until the gap passes `home_lose_radius` (hysteresis: a lost player at 300 px is not re-noticed). It keeps creeping during its warning, because the warning rule adds `home_speed`. At `home_max_distance` from its launch point it holds (it does not slide along the cap). Creep stays inside Assault's projectile rect for a launch with the cap inside it (the `ProjectileLifetime` still ends a mine launched where the cap lies outside it).
- **The sensor `Eye` sprite is a placeholder `draw_circle` in `EnemyMine._draw()`** (a yellow lens toward the player while noticing); the art task (t8) replaces it with an `Eye` sprite. Both scenes use `body_color` circles until then (blue-grey drifting, rust homing).
- Gate time: GUT 203.91 -> 204.08 s (`scripts/gate-time.sh`, 2186 -> 2201 tests; allotment 1.5 s; the 15 new rows are hand-ticked).

### Built in t4 (chain mines)
- `EnemyMine` gained `chain_radius` 150, `chain_delay` 0.2 and `shot_detonates` (all in `_reset_props()`), `chain_trigger(delay)`, `is_chained()` and `link_points() -> Array[Vector2]`. Scene `mines/chain_mine.tscn` (`variant` 3, `shot_detonates` true, `mine_life` 30, backstop 40 s, the shared 80 / 0.5 / 0.25 / 48 / 30 / 60 numbers, orange placeholder body); `EnemyMineScenes.scene_for(CHAIN)` returns it. No UIDs hand-typed.
- Propagation lives in `_on_detonated()` (after the blast, for `variant == CHAIN` only): `Hazards.around(global_position, chain_radius)`, then `info.source as EnemyMine`, not done / fizzling, then centre distance `<= chain_radius`. It calls `chain_trigger(chain_delay)` on each. `chain_trigger()` is ignored once done, fading, not launched (an idle pooled mine) or already chained, so the first delay stands and every mine emits `expired` once. `reset()` and `launch()` clear the chain state.
- A chained mine's `_update_trigger()` override counts its own clock and detonates at the delay; it skips the warning, the fizzle and the arm delay. If it was already warning, the warning stops and the chain delay decides (a chain is physical). Because chaining is by delay, a detonating mine sets off **every** neighbour including ones behind it: a mine already done is ignored, and a live one that was triggered earlier keeps its first delay.
- `shot_detonates`: `_on_health_changed()` calls `_detonate()` instead of `_defuse()` (not while fading). The blast and the propagation therefore run inside the HurtBox's `area_entered` callback; `ContactBlast.spawn()` is deferred and `chain_trigger()` only sets flags, so it is safe there. PROXIMITY and every other variant still defuse.
- Fuse links: `link_points()` returns the global positions of the live mines (any variant) within `chain_radius` as of the last refresh. A CHAIN mine refreshes on its own accumulated clock every `LINK_REFRESH` 0.5 s (first refresh 0.5 s after launch, none before), and `_draw()` draws a dashed orange line (alpha 0.35, width 1) to each; where both ends are CHAIN only the one with the lower instance id draws it. A neighbour that detonated or faded drops out of `link_points()` at once.
- Rows in `test_enemy_mines.gd` (hand-ticked, both harnesses, except the shot row at 8x): the 0 / 0.2 / 0.4 / 0.6 s ripple with the 0.8 s proximity mine and the one beyond it staying put, 149 px reached / 151 px not, skipped warning / first delay stands / done and idle mines ignored, reset clears the chain, PLAYER chain -> ALL mine pulse_damage (enemy and player), `link_points()` membership and the 0.5 s cadence, and the real-physics shot row (chain group detonates, a shot proximity mine still defuses). No deviation from plan §2.5.
- Gate time: GUT 204.93 -> 204.31 s (`scripts/gate-time.sh`, 2201 -> 2209 tests; allotment 1.5 s; the one await row is the 8x shot row; `verify.sh` GATE PASS, no leak).
- **Trap found:** `enemy_mine.gd` must not name its own `class_name` (`Array[EnemyMine]`, `as EnemyMine`, `is EnemyMine`): the script then references itself, and the whole suite reports "ObjectDB instances leaked at exit" and fails `verify.sh` while every test passes. `_chain_neighbours()` is untyped and casts to the parent `EnemyOrdnance` instead; later mine tasks (pulse, EMP, minefield) should do the same.

### Built in t6 (pulse mine)
- `mines/pulse_mine.tscn` (`variant` 4; the shared 80 / 0.5 / 0.25 / 48 numbers with `blast_damage` 8, `mine_life` 30, backstop 40 s, violet placeholder body and pop). `EnemyMine` gained `pulse_radius` 170, `disrupt_strength` 0.6 and `disrupt_seconds` 2.5 (all in `_reset_props()`), `_disrupt_players(radius, strength, seconds) -> int` (group `player`, centre distance `<=` radius, duck-typed `has_method(&"apply_boost_disruption")`, returns how many it reached) and `effect_ring_radius()` (`pulse_radius` while a PULSE mine is warning, else 0; `_draw()` draws it as a violet arc, so the ring shows during the warning). `EnemyMineScenes.scene_for(PULSE)` returns the scene. No UIDs hand-typed.
- `_on_detonated()` for PULSE: after the blast (`ContactBlast` for PLAYER, `Hazards.pulse_damage` for ALL, so 8 damage, not 30) it disrupts and spawns a `PulseRing` (`mines/pulse_ring.gd`, new): a closed violet `Line2D` built in code, no PNG, expanding to `pulse_radius` over 0.3 s on its own accumulated clock and fading, `top_level`, added to the mine's parent (so it outlives the mine) and then frees itself. `PulseRing.spawn()` returns null with no parent in the tree.
- **EMP (t7) can reuse `_disrupt_players()`'s shape** but must go through `EmpPulse.emit()` as planned; `emp_radius` is still not an export (the row helper in `test_enemy_mines.gd` falls back to 0).
- Warning rule row covers the pulse scene automatically (`blast_damage` 8 > 0 so `blast_radius` is the effect radius: 512 >= 440). The ring is *not* part of that inequality.
- Rows in `test_enemy_mines.gd`: scene numbers, 150 / exactly 170 disrupted and 180 untouched, a PROXIMITY blast disrupts nothing, the 2.5 s duration, ALL pulse deals 8 and disrupts, a hookless `player` stand-in is skipped, a real 8x row (live mine, real `ContactBlast`: ring only during the warning, 8 damage, 0.4) and a ring row (one ring, at the mine, frees itself) — each in both harnesses with the real `player_ship.tscn` / `player_fighter.tscn`.
- No deviation from plan §2.7. Gate time: GUT 205.10 -> 205.74 s (2209 -> 2216 tests; allotment 0.5 s, so +0.14 s over, within the run-to-run spread of earlier tasks; the two awaiting rows are ~0.3 s at 8x).

### Built in t7 (EMP mine and the EMP hook)
- `global/components/emp_pulse.gd` (`EmpPulse extends RefCounted`, static `emit(tree, at, radius, seconds, source) -> int`): the one EMP entry point. It calls duck-typed `apply_emp(seconds, source)` on every node in group `player` whose centre is within `radius` (`<=`, the `Hazards.pulse_damage` rule) and returns the count; a node without the method is skipped; group `enemies` is never touched in Ph7 (**Phase 9 extends the target set and keeps the signature**; `test_emp_pulse.gd` has the row it flips). It returns 0 for `seconds <= 0` (a small addition, not in the plan).
- `PlayerBase`: `signal emp_changed(active: bool)`, `apply_emp(seconds, source)`, `is_emp_disrupted()`, `_emp_left` stepped in `_step_disruption()` (via `_step_emp()`, which now runs before the disruption's own early-out). The stand-in effect is the single line `apply_boost_disruption(1.0, seconds)`, commented as **Phase 9's to replace**; Ph9 changes that line, not the signature, `is_emp_disrupted()` or `emp_changed`. `emp_changed(true)` fires only on a start (a second pulse while active is not a new start), `(false)` once at the end. Note: `is_emp_disrupted()` ends at the EMP's own time even if a longer boost disruption (a pulse mine's 2.5 s) is still running, so `boost_efficiency()` can stay 0 a little after `is_emp_disrupted()` is false. Both real ships already refused every boost verb at efficiency below `MIN_BOOST_EFFICIENCY` (t5), so no ship code changed.
- `mines/emp_mine.tscn` (`variant` 5; the shared 80 / 0.5 / 0.25 numbers, `blast_damage` 0, `blast_radius` 48 kept for the shared rule row, `emp_radius` 190, `emp_seconds` 2.0, `mine_life` 30, backstop 40 s, blue-white placeholder body and pop). `EnemyMine` gained the exports `emp_radius` 190 and `emp_seconds` 2.0 (both in `_reset_props()`), so the warning-rule helper now reads `emp_radius` instead of falling back to 0: (80 + 190) / 0.25 = 1080 >= 440. `EnemyMineScenes.scene_for(EMP)` returns the scene. No Mine Layer weight by default (`pool_size_for` gives 0 for a missing `w_emp`). No UIDs hand-typed.
- `EnemyMine._on_detonated()`: the blast (`ContactBlast` for PLAYER, `Hazards.pulse_damage` for ALL) is now guarded by `blast_damage > 0`, so a zero-damage mine spawns no blast at all (behaviour for every existing scene is unchanged: they all author damage > 0). EMP then calls `EmpPulse.emit(get_tree(), global_position, emp_radius, emp_seconds, self)` and spawns an `EmpRing` (`mines/emp_ring.gd`, new): a closed blue-white `Line2D` built in code, a jagged radius from a pure function of point index and clock (no rng), expanding to `emp_radius` over 0.35 s on its own accumulated clock, `top_level`, added to the mine's parent, frees itself. `effect_ring_radius()` now also returns `emp_radius` while an EMP mine warns, drawn in `EmpRing.COLOR`.
- Rows: `tests/unit/test_emp_pulse.gd` (6); `test_player_boost_disruption.gd` (both players: 2.0 s at efficiency 0.0 ± 1 tick, `emp_changed` arity and true-then-false, a zero-second EMP is nothing; Open Space boost + Boost Drive refused with no tank spent; Assault dash, warp and H-key Drive refused); `test_enemy_mines.gd` (scene numbers + warning rule on `emp_radius` with a synthetic boundary, 150 / 190 reached and 191 not with zero Health damage and no blast in both harnesses, an ALL EMP mine deals no `pulse_damage`, proximity / pulse blasts apply no EMP, a real 8× mine reaches the real player with the ring only during the warning, the crackle ring spawns at the mine and frees itself).
- No deviation from plan §2.8. Gate time: GUT 205.31 -> 206.16 s (2216 -> 2233 tests; allotment 1.0 s; the "before" was measured on a clean `git archive HEAD` copy because edits had already started).

### Built in t10 (Mine Layer shell)
- `assault/scenes/enemies/mine_layer/`: `mine_layer.tscn` (r 40 circle shared by body / `HurtBox` / `ContactHitBox`, stern `Dispenser` at (0, −38), `StateLight`, `EnemyMover` + `Brain`, root pools `ProximityPool` 20 / `ChainPool` 6 / `PulsePool` 5 / `HomingPool` 5, all `persist_after_owner_death`, placeholder `bomber.png` hull scaled 0.92), `mine_layer.gd` (`MineLayer extends BaseEnemy`; joins group `enemies`; `drop_mine(variant, rest_point) -> EnemyMine`; `_process` rail fallback), `mine_layer_brain.gd` (`MineLayerBrain`, `Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }`, `signal phase_changed(new_phase: int)`, `enter_phase()`, `start_engaged`; shell plays APPROACH and DISENGAGE only), flat `MineLayerConfig` + `.tres` (hazard_avoidance 0.8 / margin 24 / resistance 0.2, wreck 0.35 medium; no trigger / warning / blast fields), `ENEMY.md`. `WaveBuilder.MINE_LAYER` + `mine_layer()`. Added to the four hand rosters (contact damage, contact geometry, hurtbox geometry, `test_wreck.gd` `_SHIP_SCENES`); the config-isolation sweep finds it itself. No UIDs hand-typed.
- `drop_mine()` sets only `arm_delay`, `eject_time` and the life by mode (`EnemyWorld.arena()` present = Assault: `mine_life` 9.0; else `mine_life` 0 and the `ProjectileLifetime` backstop 240). Falls back to `ProximityPool` when a variant's pool is absent or exhausted; null when nothing could be acquired. The rail fallback forces the Assault life (a rail is an Assault thing).
- **Deviation 1 (eject maths):** the launch speed is `2d / (eject_time − 1/physics_ticks)`, not the Bomber's `2d / eject_time`. A mine moves in discrete ticks and decays on its first one, so the bare formula stops `d·dt/T` short (8 px at 146 px); the plan's "stops within 4 px" needs the correction for long ejects. At the Bomber's own distances the two agree within a pixel or two. **t11's rest points can be any distance and need no extra allowance.**
- **Deviation 2 (contact hitbox mask):** the plan says the `ContactHitBox` is "mask 128"; every COLLISION-profile enemy (Bomber, Fighter, Missile Corvette) authors `collision_mask = 0` and only RAMMING ones (Ram) use 128, so the layer follows the COLLISION idiom (layer 256, mask 0). The contact-damage and geometry gates pass on it.
- DISENGAGE: `_enter_disengage()` calls `mover.release_constraint()` and sets `mover.max_speed = exit_speed`; the exit direction is fixed on entry (velocity direction, else the facing `Vector2.RIGHT.rotated(rotation + sprite_forward_angle)`), and the layer frees itself outside `projectile_world_rect()` only when a rect exists (never in Open Space). Row proof: without the release, `test_mine_layer.gd` fails both the `constraint_released()` row and the "leaves the world rect" row.
- `MineLayerBrain.start_engaged` exists but nothing reads it yet (the hub idle task does). The live-mine cap (`max_live_mines` / `assault_max_live_mines`, `EnemyMine.retire()`) is in the config but not used by the shell; the pass task applies it.
- Gate time: GUT 206.04 -> 207.86 s (2233 -> 2251 tests; allotment 1.5 s, +0.3 s over, inside run noise).

### Built in t8 (Minefield)
- `assault/scenes/hazards/minefield/`: `minefield.tscn` (`Minefield extends Node2D`: `Mines` + `Beacon`), `minefield.gd`, `minefield_beacon.gd` (`MinefieldBeacon`: code-drawn amber blink, `lit`, `blink_alpha()`; it draws nothing itself once a `Sprite` child has a texture, so the art task only adds that sprite), `HAZARD.md`. Patterns AUTHORED / RING / GRID / SCATTER, flat `w_*` weights drawn with the field's own seeded rng (per mine: position, then variant, then a drift direction), `hostility` ALL by default, `drift_leash` 120, `assault_drift_speed` 60, `spawn_into(container, at)` (deferred, a freed container frees the field). Every mine gets `placed = true` and the field's hostility; the field never sets `placed_life`. A non-`EnemyMine` child under `Mines` is a `push_error` and is left alone. The field frees itself 1 s after the last mine (`DARK_TIME`) and in Assault below the world rect or after 40 s (`ASSAULT_MAX_LIFE`). No level-1 placement.
- **Deviation (additive, `EnemyMine`):** a new public `carry_velocity: Vector2` (setter `set_carry_velocity()`), added to the mine's own motion in `HazardInfo.velocity` through `_set_velocity()` (the seven former `_info.velocity = ...` writes now go through it). A moving `Minefield` sets it to `(0, assault_drift_speed)` on every mine each tick. Without it the avoidance stage could not lead a mine carried by the scrolling field, and the avoidance-0.8 fixture got to 131–139 px from a mine centre in Assault (plan §2.3 measured >= 155 for a still field). The mine never moves itself by it, and with `carry_velocity` zero every existing row is unchanged. **Later tasks that move a field or a parent of mines (t13 hub field, t14 level-1 layer) need nothing; anything else that carries mines should set it.**
- AUTHORED drifting mines keep an authored direction and leash and get the field's only where they have none (the plan did not say; a standalone drifting mine with a zero direction is still).
- **Test geometry note (Assault avoidance row):** the avoidance-0.8 fixtures and the stub fly *with* the scroll, `(240, 60)`, i.e. the same straight line across the field as in Open Space. A ship that flies level while the field scrolls down crosses it on a slant, which is a different (and worse) measurement than the plan's. The fixtures do not get across a 9-mine ring in the time the row runs (the context stage slides them along its wall, as §2.3 says); the row asserts closest approach, no mine set off and no damage, not arrival.
- Rows: `tests/integration/test_minefield.gd` (20 tests: ring 9 on 200 px +-0.5, grid spacing / count / centring, seed-stable scatter, weights and the all-zero fallback, AUTHORED positions and the ready-order boundary (placed = false / PLAYER end placed and ALL after one frame), a PLAYER-hostility field, the stray child, a 60 s hand-ticked run of a proximity + drifting ring (every mine ALL, placed, registered, alive, not fizzling, `mine_life` 0 although `mine.tscn` authors 8.0; drifting mines move and stay within 121 px), seeded drift directions, beacon dark + free after 1 s, `spawn_into` and a freed container, Assault drift 60 t with `HazardInfo` position and velocity following, world-rect cleanup at the lowest mine, the 40 s cap, an Open Space field standing still, and both modes at 8x: stub set off, avoidance-0 fixture set off and damaged, avoidance-0.8 / margin-24 fixtures at lateral 0 / 100 / 200 set off nothing and stay >= 140 px from every mine centre). `tests/unit/test_hazards.gd`: a field adds `count` hazards and removes them when freed.
- Gate time: GUT 206.64 -> 208.11 s (2251 -> 2272 tests; allotment 1.5 s, +1.48 s). The "before" is a clean `git archive HEAD` copy.

### Built in t9 (mine art)
- Art (PixelLab `create_image_pixen`, 24 x 24, `view: "high top-down"`, `no_background`, single-colour black outline; saved through `scripts/pixellab.sh`) in `assault/assets/sprites/projectiles/mines/`: `mine_proximity.png` (round ball, ring of spikes), `mine_drifting.png` (disc, two side fins), `mine_homing.png` + `mine_homing_eye.png` (16 x 16 amber lens), `mine_chain.png` (hexagon, three prongs), `mine_pulse.png` (coil ring round a violet core), `mine_emp.png` (loop antenna, blue-white core), `minefield_beacon.png` (32 x 32 buoy ring with an amber lamp). No glow is painted in: the red armed blink, yellow warning blink, effect ring and chain links stay code-drawn on top (the `Sprite` is `show_behind_parent`).
- Every mine scene has a `Sprite` (`Sprite2D`); the Bomber's `mine.tscn` wears the proximity sprite. `body_color` is gone from all six mine scenes (the `EnemyOrdnance.body_color` export stays: the gravity and pursuit bombs still use it), and `body_radius` is 8 -> 11 on the six mine scenes so the armed / warning overlay fits the 24 px sprite (look-only; no row read 8).
- **Deviation (small):** the homing mine's placeholder `draw_circle` eye became an `Eye` `Sprite2D` child of `homing_mine.tscn` (hidden unless noticing, nudged `0.4 * body_radius` toward the player by `EnemyMine._update_eye()`, called from `_draw()`); no other variant has an `Eye`.
- **Beacon:** `minefield.tscn`'s `Beacon` now has a `Sprite` child (`minefield_beacon.png`); `MinefieldBeacon` lost its code-drawn amber placeholder (`AMBER` / `RADIUS` are gone) and only blinks / hides the sprite (alpha 1.0 / 0.35 at 1 Hz; hidden when `lit` is false). A `MinefieldBeacon` with no `Sprite` child draws nothing.
- Chosen from several candidates per sprite (the first chain / drifting / beacon / proximity results were a four-prong cross, a ship-like capsule, a front-view robot-looking buoy and dark-on-dark spikes). The drifting sprite has fins but no visible nozzle.
- Rows: `test_enemy_mines.gd` (every variant scene has an opaque centre, transparent corners, its own texture and no `body_color`; no two sprites share a silhouette; the homing eye shows only while noticing) and `test_hazard_art.gd` (the beacon: size, opaque centre, transparent corners, scene wiring and blink). `test_entity_sprite_transparency.gd` reaches the mine and minefield scenes through its existing `projectiles` / hazards sweep and stays green.
- Gate time: GUT 207.49 -> 207.86 s (2272 -> 2277 tests; allotment 0.5 s, +0.36 s). The "before" is a clean `git archive HEAD` copy.

### Built in t11 (Mine Layer passes)
- `MineLayerBrain` (`mine_layer_brain.gd`) plays the pass AI of plan §2.12: APPROACH (seek R, then the run-in R -> S) -> LAY -> BREAK_OFF -> REPOSITION in Open
  Space, one pass then DISENGAGE in Assault. Task plan (escalated, independently reviewed, R3 APPROVED): `docs/plans/cmvkb0hdc00uiqs2xhvb2awai/3-plan.md`.
  Names later tasks build on: `enum Shape { ZIGZAG, ARC }`, **`signal mine_dropped(mine: EnemyMine)`** (every drop the brain makes, pass and tail; t13's wake
  can read it), consts `ARRIVAL_SCAN_STEP` 0.1 / `ARRIVAL_BISECTIONS` 5 (re-declared, not borrowed from the Bomber), `SPREAD_EXTRA` 10, `REPOSITION_LEAD` 0.4,
  `NO_STACK_PAD` 40, `CHARGE_TIME` 0.3, `TIE_PX` 1, `STALL_FACTOR` 1.2 / `STALL_SLACK` 0.5, `RUN_IN_STALL_SECONDS` 20; the seams listed in `ENEMY.md`
  (`pass_form` is `&"lead"`, `&"fence"` or `&"assault"`). `lay_mine(variant, rest)` is the only way the brain lays (it keeps the live FIFO and `retire()`s the
  oldest at `max_live_mines` / `assault_max_live_mines`); `MineLayer.drop_mine()` is unchanged. `MineLayerConfig` gained `@export_group("Passes")` (the task
  plan's 27 flat fields, script defaults = §2.12's numbers, `.tres` unchanged).
- **Addition (`EnemyMine`):** `is_live() -> bool` (`_launched and not _done and not _fizzling`); a recycled pooled mine reads false until its next launch.
- **Pre-approved lever used (§2.12, the acceleration-limited form of the task plan):** LAY drives the mover through
  `mover.boost(v.normalized(), v.length(), delta)` with `v = own_velocity().move_toward(aim_dir * lay_speed, acceleration * delta)`, every tick. Forced by
  `test_mine_layer.gd::test_lay_flies_sideways_and_on_the_path` "earlier pass" (an older ZIGZAG line crossing the new one near its E end): with plain
  `request_velocity()` avoidance turned the layer **85.5 deg and 178.2 px** off its line; with the lever 32.7 deg / 11.4 px, the same as with no older line.
  Consequence for later phases: **in LAY the Mine Layer skips the avoidance stage** (hazard slow and drift still apply); it crosses an older line, and a placed
  `ALL` minefield in its path can set it off (PLAYER mines cannot).
- **Changed row (premise):** `test_enemy_dual_mode.gd::test_mine_layer_approach_closes_on_the_player` became
  `test_mine_layer_approach_closes_on_its_run_in_point`: APPROACH now seeks R (450 px beside the line's centre), so from (640, 60) the layer can fly away from a
  player at (640, 360). It asserts the gap to `pass_run_in_point` closes by > 60 px in 1 s, phase still APPROACH, Assault inside the soft band.
- **Pinned in the task plan (not in §2.12):** the abandon guard (Open Space: a frozen R not reached is given up to REPOSITION, `abandoned_passes` + 1, after 6 s
  within `commit_distance` without a run-in, 12 s never within it, or 20 s in the run-in); BREAK_OFF raises `mover.max_speed` to `break_speed` (the mover caps
  every request at `max_speed`); no-stacking is checked at drop time against every live mine (`Hazards.around()` plus this layer's FIFO), this pass's own exempt;
  the tail cone is ±30 deg about the stern and DISENGAGE counts as engaged; DISENGAGE after a pass exits along `pass_axis`; an ARC pass's mine 5 always drops at
  the end (the plus rule would need the centre at 662.6 px of a 656.6 px path). Small addition: the tick a LAY ends also ticks BREAK_OFF / DISENGAGE, so no
  tick passes with no request.
- Measured (seed 4242, hand-ticked): standing fence plans freeze on tick 101 (1.68 s) at 0 / 90 / 180 deg; the lead plan 600 px ahead of a 100 px/s stub freezes
  on tick 92 with C 190 / 133 px ahead of the stub when mines 2 / 3 arm; abeam on tick 232 (3.87 s). 60 s standing scenario: 4 passes, 0 fence / 0 spread
  fallbacks, 0 abandoned, live peak 18, closest approach to a live mine of an earlier pass outside LAY / BREAK_OFF 151 px. 60 s circling scenario (120 px/s on a
  700 px circle): 3 passes, 3 fence fallbacks (a 120 px/s player abeam 700 px away is out of the 6 s scan's reach), 1 abandoned pass, 0 spread fallbacks. The
  task plan's risk that the 4th standing pass "almost always" takes the spread fallback did not show with this seed (a legal rotation was left).
  Assault (harness, player at (640, 360), layer from (240, 300)): LAY 2.07 -> 5.83 s after spawn (3.77 s for the pass), then DISENGAGE along the axis; freed 7.57 s after spawn. Open Space standing (bearing 0): LAY 3.93 -> 7.70 s.
- For t12 (hub idle): every t11 row sets `start_engaged = true`; `tick()` does not dispatch IDLE / NOTICING / RETURNING yet. For t13: the StateLight goes
  CHARGING 0.3 s before each drop and ARMED for the rest of LAY; the hatch and the wake are t13's. For t15: one pass per Assault life; the budget defers to the end
  of LAY, bounded by the stall guard (<= 5.67 s for ZIGZAG).
- Gate time: GUT 207.67 -> 209.85 s (2277 -> 2301 tests; allotment 4.5 s, +2.18 s; `test_mine_layer.gd` 0.77 -> 2.09 s on its own). The "before" is a clean `git archive HEAD` copy.

### Phase 7, built in t12 (Mine Layer hub idle and Open Space persistence) (2026-10-27)

Plan §2.14 as written, with these notes. Tests: `tests/integration/test_mine_layer.gd` (the "t12" section at the end).

- **`MineLayerBrain` gained the Bomber's hub idle:** `patrol_anchor` (`Vector2.INF` = the spawn), `anchor_idle: AnchorIdle` (built in `_setup()` when `not budget.active and
  not start_engaged`; `on_suspended()` drops it), `idle_phase_offset` (from `rng`, +-`MAX_IDLE_PHASE_OFFSET` 0.35), `_tick_anchor_idle()` ahead of the tail drop and the phase
  dispatch. `Phase` is unchanged (IDLE / NOTICING / RETURNING were already declared). `MineLayerConfig` gained `@export_group("Idle")`: `perceive_radius` 650, `lose_radius` 1500,
  `notice_time` 0.35, `idle_radius` 160 (also AnchorIdle's `home_radius`), `idle_speed` 0.5; `.tres` unchanged.
- **NOTICING hands over to REPOSITION, not APPROACH.** §2.14 says NOTICING "redraws the pass period, so a layer that idled for a minute does not lay the instant it notices": the
  pass period is REPOSITION's `pass_period_min..max` wait, and `_enter_reposition()` already draws it afresh, so the layer orbits the player at `standoff_range` for 5-7 s first.
  (§2.14's inequality-1 prose mentions APPROACH starting "from NOTICING inside `perceive_radius`"; with REPOSITION first the start is at most 650 px away either way, so
  inequality 1 and the 1415.8 figure are unaffected.) Row: `test_perceiving_the_player_notices_for_a_beat_then_waits_out_a_fresh_pass_period`.
- **Not interrupted by an idle transition:** LAY (the spec) **and DISENGAGE** (already leaving; Open Space reaches it only through a test seam). Every other engaged phase goes
  RETURNING when `AnchorIdle` says so. Entering IDLE / NOTICING / RETURNING restores `mover.max_speed = max_speed` (BREAK_OFF raises it to `break_speed`).
- **Existing rows:** the pre-t12 rows that spawn a layer in Open Space and expect combat now set `start_engaged = true` (`_spawn` and `_pass_layer`'s default in
  `test_mine_layer.gd`; the dual-mode APPROACH row). `_pass_layer(..., engaged = false)` is the cold start.
- **Persistence needed no production change:** `drop_mine()` already gives Open Space mines `mine_life` 0 and a 240 s backstop, and RETURNING never touches mines. The row
  `test_open_space_mines_persist_while_the_player_is_away_and_trigger_on_return` proves it: a pass, the stub teleported 2000 px from the layer, RETURNING and home, 60 s of game
  time, every mine at its rest point (< 0.5 px) and registered, then a stub placed 300 px short of the line and driven through it at 220 px/s (8x real physics) sets off the first mine
  it reaches (within 0.12 s of the geometric entry time). Homing is weighted out of that one scenario (`config.w_homing = 0` on the layer's private copy) so no mine creeps toward the
  returning stub. The Assault counterpart (`test_assault_mines_are_gone_after_assault_mine_life`) shows each mine live until its `assault_mine_life` of 9 s and gone, unregistered, after.
- For t13 (hub placement): a hub layer needs `patrol_anchor` only if it should not patrol where it spawns; its pools hand its mines over on death as in Assault. A pickup or
  trigger placed within `perceive_radius + idle_radius` (810 px) of the layer's anchor will wake it, as the Bomber's hub sweep already assumes.
- Gate time: GUT 211.66 -> 210.04 s (2301 -> 2312 tests; allotment 1.5 s). The "before" is a clean `git archive HEAD` copy. `test_mine_layer.gd` alone went 2.09 -> 2.87 s
  (+0.8 s); the whole-suite difference is run noise.

### Phase 7, built in t13 (Mine Layer hull art, dispenser hatch and wake) (2026-10-27)

- **Art:** `assault/assets/sprites/enemies/mine_layer.png` (96 × 96) and `mine_layer_hatch.png` (64 × 32), both PixelLab `create_map_object`, `view: "high top-down"`,
  saved through `scripts/pixellab.sh`, imported and looked at at 6× and in an in-game composite (strict top-down, no side face, nose-down, transparent corners). Four hull
  candidates and two hatch candidates were generated. The chosen hull is a wide shield with a full-width stern rack; two others came back nose-up or too narrow.
  The `Sprite2D` lost its π rotation and 0.92 scale (the bomber placeholder was nose-up); the hull draws at 1.0.
- **Hatch:** a `Hatch` `Sprite2D` at (0, −34), scale (0.92, 0.55). `MineLayer.set_hatch_open(open)` / `hatch_open()`; `scale.y = closed × max(1 − open, 0.001)`. The brain
  eases it in `tick()` (`_ease_hatch`) over the new config field `hatch_seconds` 0.25. **Config fields added** (group "Art"): `hatch_seconds` 0.25, `wake_fade` 2.5.
- **Wake:** `MineWake` (`mine_wake.gd`), `class_name MineWake extends Line2D`. `MineWake.spawn(dispenser, fade)`, `step(delta)`, `finish()`, `global_points()`, `SPACING` 12.
  The brain keeps it in `brain.wake` (null before the first LAY) and calls `finish()` from `enter_phase()` for any phase but LAY. It is a child of the layer's *parent*
  (the enemy container), so it survives the layer. Points are interpolated at exactly 12 px along each tick's straight run, so the "two points per 24 px" bound holds at any speed.
- **Tests:** `test_mine_layer.gd` gained 10 tests, 16 rows in both modes (hull opacity, hatch scale and ease, wake spacing / path offset (worst 0.32 px) / fade / self-free / dead layer / container).
  The hatch and wake rows read the shared `_natural_pass` scenario, extended with per-tick hatch and dispenser records and a hand-stepped wake; no new scenario was run.
- **No deviations** from plan §2.13. The plan's "scale tolerance" is 0.01.
- Gate time: GUT 210.55 -> 209.99 s (2312 -> 2322 tests; allotment 0.5 s); `test_mine_layer.gd` alone 2.90 -> 2.92 s. The "before" is a clean `git archive HEAD` copy.

### Phase 7, built in t14 (hub Mine Layer patrol and the placed minefield) (2026-10-27)

Plan §2.15 as written, no deviations.
- **Patrol:** `SectorHub._spawn_patrol()` appends `_spawn_mine_layer(_mine_layer_anchor(), rng)` as draw 15 (after the Support Ship's 14). New exports `mine_layer_ring_radius` 2600 and
  `mine_layer_anchor_bearing_deg` -22.5, anchor (2402.3, -995.1). `patrol_anchor` and the brain's `rng_seed` are set before `add_child()`. Every earlier seed is unchanged.
- **Field:** `TacticalSpace/Minefield` in `sector_hub.tscn` at (3300, 560): RING, 9 mines, radius 200, `rng_seed` 7, weights proximity 0.4 / chain 0.3 / drifting 0.15 / EMP 0.15, hostility ALL. The
  `ext_resource` has no `uid` (the scene file mints none by hand).
- **Clearances (printed by the tests):** the Mine Layer anchor clears the nearest interactable by 1036.3 px past idle + perceive (nearest 1846.3 px); the field (element radius 400 = 200 + 120 drift leash +
  80 proximity trigger, read from `EnemyMineScenes.export_of`) clears the Mine Layer group by 585.6 px and the Gatling group by 775.1 px; the Mine Layer's nearest anchor is the Missile Corvette's, 1114 px away.
- **Tests:** `test_sector_hub_patrol.gd` gained the Mine Layer in `_patrol_groups()`, the `Minefield` case in `_element_radius()`, the ring row, the nine-anchor spacing row (renamed from "eight"), the seed row
  (draw 15), the composition / container-count / frame-0 IDLE rows, a hub-field row, a field-clearance row with a rejecting boundary, a 60 s hub-field liveness row (hand-ticked; all nine mines, the
  PROXIMITY ones built from `mine.tscn`, still placed / ALL / registered / not fizzling) and "a hub Mine Layer's mine lands in `EnemyContainer`" (the engaged layer is hand-ticked until it lays, then 30
  real physics frames on the 8x clock).
- **Hub frame time** (headless `Performance.TIME_PHYSICS_PROCESS + TIME_PROCESS`, 600 frames, full `sector_hub.tscn`): about 7.3 ms mean with the layer and the field live against about 5.5 ms with both
  removed (two runs), i.e. roughly +1.8 ms of script time per frame for the layer, its idle, nine mines and the extra hazard registrations. No rendering is included.

### Phase 7, built in t15 (level 1 Mine Layers) (2026-10-27)

- **Placement:** `b.mine_layer().at(-400, -160)` inside `deep_space`'s existing 16.0 s wave and `b.mine_layer().at(400, -160)` inside `planet_approach`'s existing 47.0 s wave
  (`level_1_director.gd`). AI spawns, no `.move()` / `.free_after()`, no new wave, so no other wave's effective trigger moved. None is in an ENEMIES_CLEARED section.
- **Gates:** `test_level1_specialist_spawns.gd` gained `EXPECTED_PH7` (2 rows) with its row-count, shared-wave, delay and no-rail rows; the layer is merged into `_ai_lives()` as a specialist
  (life = `engage_seconds` + the ZIGZAG stall guard 5.67 s + `_TICK_SLACK` + the measured corridor exit **7.53 s**, from `SpecialistExitProbe` at `[exit_speed, 10]` over 2166 runs); `_spills()` adds
  `assault_mine_life` for a layer (`_ordnance_tail`). Peaks: deep_space **8** (limit 12.5), planet_approach **7** (limit 7.5); an extra layer at planet_approach's peak (98.0 s) takes it to 8 and fails.
  Spill-over: deep_space's last specialist or mine is gone 47.2 s into its section, planet_approach's 116.4 s, against ENEMIES_CLEARED last triggers at 60.0 s and 186.0 s.
  `test_engagement_deadline.gd` gained "no ENEMIES_CLEARED section spawns a Mine Layer", a detection row and a boundary (a layer at delay 0 in cloud_descent computes 18.5 s of a 10 s timeout).
  `test_mine_layer.gd` gained the attack-in-budget slice replays (8x): from both spawns the layer reaches LAY with 6.3 s of budget left, lays 6 mines, all 6 inside `view_rect()`, one pass per life;
  a 2.0 s budget reaches no LAY.
- **Probe preparation (deviation from "plain probe"):** the layer's probe instances skip pool prewarming and set `config.tail_range = 0`. The probe reuses one world for 2166 runs and mines persist after
  their layer (`persist_after_owner_death`), so tail mines left by one run sit in the way of the next and the first attempt measured 20 s (capped) instead of the real exit; a tail mine behind an
  exiting layer does not change its exit (3 s with and without in a single run). The probed layer reports `constraint_released()` and `max_speed == exit_speed` (asserted).
- **No offset or wave had to move.** No deviation from plan §2.16.
- Gate time: GUT 210.86 -> 220.65 s (2329 -> 2344 tests; allotment 8.0 s, used about 9.7 s): `test_level1_specialist_spawns.gd` alone 13.3 -> 20.7 s (+7.4 s, nearly all the layer's 2166-run exit probe
  in `before_all`: 2166 instantiations and about 650k hand-ticks) and `test_mine_layer.gd` 2.9 -> 5.2 s (+2.3 s, two slice replays and one boundary replay). The probe grid is the plan's, so it was
  not cut; 1.7 s over the task's allotment, 19.4 s under the 240 s ceiling.
