# Decision log — Enemy rework (idea cmufkkgmx0001o02y6bnf52bq)

Running log shared by every phase epic of this idea. Each phase appends; nothing earlier is rewritten.
Where a phase's *as built* section disagrees with its plan section, the *as built* section wins.

## Phase 1 - Enemy rework, phase 1: mode-neutral enemy AI architecture and plan for the full roster (2026-09-25)

Plan: `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md`, with research in `1-context.md` and `2-research.md` in
the same directory. The 17-phase roadmap is in §7 of the plan, and the requirement → phase coverage table is in §8.
These are *planned* decisions; check this phase's `as built` section, once written, before relying on them.

### Names and places (later phases build on these)
- `EnemyMover` (`global/enemy_ai/enemy_mover.gd`) is the enemy movement component.
  - **Never `MovementController`.** That name is the player's input handler.
  - When active, it is the **single writer** of an AI enemy's `velocity` and `rotation`, and it performs the one
    `move_and_slide()`.
- `EnemyBrain` (`global/enemy_ai/enemy_brain.gd`) exposes `tick(delta)`, `on_suspended()`, `actor`, `mover`,
  `attack` and `rng`.
  - `rng` is a seedable `RandomNumberGenerator` (the `rng_seed` export).
  - Concrete brains extend it and live beside their enemy, e.g. `drone_interceptor_brain.gd`.
- `Steering` (`global/enemy_ai/steering.gd`) holds pure static primitives that return a desired velocity:
  seek, arrive, orbit, intercept, evade, retreat_from, strafe, hold_position and drift.
  - `boost` is stateful and lives on `EnemyMover`.
  - Deferred to later phases: `spiral`/`corkscrew`/`formation_slot` → Ph2, `lead_target` → Ph3 (it is
    `TargetInfo.aim_direction`), `break_contact` → Ph4, `regroup` → Ph14.
- `MovementConstraint` (`global/enemy_ai/movement_constraint.gd`) is the identity `filter(pos, desired) -> Vector2`.
  - `AssaultCorridorConstraint` (`assault/scenes/systems/`) extends it with a soft band of 120 px, a hard band of
    450 px and an "entered" latch, so spawns can enter from off-screen.
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
  - It emits the host's `expired` once and **never frees**, which preserves the one-owner rule.
  - `persist_after_owner_death` is documented only. It becomes a `BulletPool` policy in Ph5.
- `CollisionLayers` (`global/physics/collision_layers.gd`) holds the named constants. The layer names are:
  `environment` 1, `environment_interactable` 2, `environment_player` 4 (typo fixed), `pickups` 16,
  `player_rockets` 32, `player_hitbox` 64, `player_hurtbox` 128, `enemy_hitbox` 256, `enemy_hurtbox` 512,
  `hazard_contact` 1024.
  - **No numeric value changed.**
  - No new layer is allocated until something uses it. Ph6 allocates `area_control` (bit 12, 2048).
  - Bosses get no layer of their own; their modules are ordinary enemy hurtboxes.

### Conventions
- **How the mode is detected:** the world declares it. `ArenaCamera` joins the group `&"assault_arena"` and answers
  `enemy_movement_constraint()` (a new instance per call) and `projectile_world_rect()` (today's EnemyBullet
  bounds, x −164…1444, y −444…1164).
  - With no provider, the mode is Open Space: no constraint and no rect.
  - Nothing under `global/` may reference the `ArenaCamera` class.
  - Tests inject the constraint or rect directly.
- **Brain ticking:** brains tick on **physics**, from `BaseEnemy._physics_process`, in the order `brain.tick` then
  `mover.step`.
  - Clocks are accumulated `delta` values. There are no `Timer` nodes, and randomness comes only from `brain.rng`.
  - Legacy subclasses that define their own `_physics_process` are untouched.
- **Rails:** `EnemyPathMover` suspends AI by calling `suspend_ai()`, with the `"AIStateMachine"` name lookup kept
  as a fallback.
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
  - In Assault it keeps the legacy camera cull via `AssaultCorridorConstraint.is_past_cull()`.
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
| Retiring `EnemyPathMover` as the default | Ph15 | |
