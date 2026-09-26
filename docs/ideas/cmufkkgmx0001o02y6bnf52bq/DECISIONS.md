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
