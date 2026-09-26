# Enemy rework, phase 1: mode-neutral enemy AI architecture — PRD

## The ask

> Enemy rework, phase 1 of 20: mode-neutral enemy AI architecture and plan for the full roster.
> This epic comes from two attached documents. `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` proposes a
> full redesign of the enemy roster so that enemy AI works in world space and treats Open Space as
> the source of truth. Assault would reuse the same AI inside a corridor movement constraint
> instead of camera-relative paths. `ENEMIES.md` is the current-state audit
> (`docs/enemy-rework/current-enemies.md` in the repo). It shows why this is needed: `EnemyPathMover`
> turns off enemy AI and ties movement to `ArenaCamera.WORLD_SCALE` and screen-edge culling.
> `EnemyBullet` despawns at fixed arena bounds, `BaseEnemy` overwrites every hurtbox mask with
> `97|1024`, collision bits 6 and 11 have no names, `BulletPool` assumes the node two levels up is
> the container, and Open Space's only enemy is a `PatrolDrone` that drifts in a straight line.
>
> The documents cover much more than one epic: an architecture layer (`EnemyBrain`,
> `MovementController`, `AttackController`, `DefenseProfile`, `TargetInfo`, hazard perception,
> world-space projectile lifetime, contact-damage profiles, squad communication, idle behaviour),
> about 10 reworked or new enemies, battlefield structures (turrets, jammers, gravity wells, mines,
> twin-laser drones, wrecks), a modular carrier and two bosses (a Space Fortress rework and a
> Dreadnought), an Open Space `EncounterDirector`, an Assault migration, a readability pass on the
> art, difficulty scaling, and a test strategy. They also give a seven-phase implementation order.
>
> As the author asked, the preparation stage should analyse all of these ideas, put any proposed
> improvements to them at the top of the plan, and write a full roadmap to `docs/plans/<epicId>/`
> that splits the rest into follow-up epics. This epic's implementation scope is only Phase 1, the
> architecture: make `BaseEnemy` mode-neutral; add the brain, movement, attack and defense contracts
> with movement primitives and an Assault movement-constraint wrapper; replace camera-bound enemy
> projectile lifetime with world-aware lifetime; name every collision layer in use and swap the
> hardcoded hurtbox mask for a `DefenseProfile`; and add `TargetInfo` prediction helpers. Existing
> assets must be kept: `ShipConfig.privatise`, shared components, attack patterns and bullet pools,
> the Drone Interceptor's orbit and dash, the Space Station's modular boss structure, and the Bonus
> Drone as an Assault reward target. Existing Assault waves must keep working while the change
> lands, and it must pass the current invariant gates. It also adds deterministic GUT coverage for
> `BaseEnemy`, `EnemyPathMover` and `PatrolDrone`, which have none today, plus tests that run the
> same behaviour in both modes. Still open: the numeric layer allocation, whether `DamageReaction`
> replaces the damage flow inside `BaseEnemy`, and the difficulty tiers.

### Original idea

> Analyze the files with ideas, add improvements to it if you have any great ideas, research and
> create a plan to implement ALL those ideas. Be sure, to add in the review all changes you
> proposed at the top of the document, if you have any. `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` — file
> with all ideas proposed. `ENEMIES.md` — current implementation.

Attached documents, quoted throughout planning and preserved verbatim in the repo:
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` and
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`.

### Human feedback (plan review, verbatim intent)

Round 1 of the independent plan review returned `CHANGES_REQUESTED` with eleven findings (F1–F11),
seven of them blocking: a `ProjectileLifetime` design that would silently break the sniper's
unpooled shot (F1); a wrong `max_time` derivation that could trip before the legacy rect on the
slowest shipped bullet (F2); a "fallback" reading of the path-mover's `suspend_ai()` contract that
could silently stop suspending the light assault ship's state machine (F3); an incomplete
edge-band specification for the Assault corridor and no decision on the ported Drone Interceptor's
constraint mode (F4); two task-graph file collisions with no ordering (F5); several factual errors
about what the shipped code and tests actually do (F6); and a mismatch between the roadmap's phase
count and the board (F7). Round 2 reviewed the revision and returned `APPROVED`, with seven
non-blocking notes (N1–N7) folded into task descriptions rather than requiring a third round. Both
rounds are preserved in `docs/plans/cmufklb100001p92xs1ey2fb1/4-review.md`.

## Player-facing goal

None directly — this phase is architecture with no new enemy, encounter, or visible behaviour
change. The one player-observable proof is that the Drone Interceptor, already shipped in Assault,
now also chases the player in Open Space (previously Open Space had no hunting enemy at all, only
a straight-line-drifting `PatrolDrone`). Everything else is the foundation later phases build the
actual roster rework on.

## Scope

**In scope (this phase):**
- `BaseEnemy` becomes mode-neutral: a brain/mover tick loop, `suspend_ai()`, documented virtual
  damage/death hooks, one facing rule, a verbose-gated death log, `ShipConfig` export groups.
- `EnemyBrain` + `EnemyMover` contracts, `Steering` primitives (seek, arrive, orbit, intercept,
  evade, retreat_from, strafe, hold_position, drift; `boost` on the mover), `MovementConstraint`
  (identity) and `AssaultCorridorConstraint` (soft/hard band velocity filter).
- `TargetInfo` (player resolver + intercept/prediction + `accuracy`-blended aim).
- `DefenseProfile` (per-instance hurtbox mask/damage-type data, replacing `BaseEnemy`'s hardcoded
  `97|1024`) and `CollisionLayers` (named constants for every used bit).
- `ProjectileLifetime` (world-space `max_time`/`max_distance`/`world_rect` rules), migrating
  `EnemyBullet` off its hardcoded arena bounds.
- `EnemyWorld` + the `&"assault_arena"` group as the one mode-detection seam, answered by
  `ArenaCamera`.
- `AttackController` extended (`enabled`, `driven_by_brain`, `fire_now()`) and `accuracy` on the
  aimed/gatling patterns.
- The Drone Interceptor ported onto the new contracts (`constraint_mode = NONE`) as the proof
  consumer, playing identically in Assault and newly functional in Open Space.
- Deterministic GUT coverage for `BaseEnemy`, `EnemyPathMover`, `PatrolDrone` and the Drone
  Interceptor (none existed before this phase), plus a dual-mode harness that runs one behaviour
  spec in both an Open Space and an Assault test world.
- The 20-phase roadmap for the rest of the idea, in `3-plan.md` §7/§8, and this dossier.

**Explicitly out of scope (deferred to named later phases — see DECISIONS.md's "Deliberately
deferred" table for the full list):** any new or reworked enemy roster entry beyond the Drone
Interceptor port; `DamageReaction` replacing `BaseEnemy`'s inline damage flow; hazard perception,
gravity wells, mines, turrets, jammers; the Carrier, Heavy Gunship rework, Space Fortress 2.0 and
Dreadnought; an Open Space `EncounterDirector`; the Assault migration off `EnemyPathMover`'s
rail-driven waves; difficulty tiers (only the `accuracy` hook exists); the art readability pass;
and `BulletPool`'s grandparent-container assumption.

## Constraints

- **View rule:** N/A — this phase shipped no art.
- **Coordinate space:** Assault waves stay authored in 640×360 design units scaled by
  `ArenaCamera.WORLD_SCALE`; nothing in this phase pre-multiplies that scale into new code.
- **Reuse requirements (explicit in the brief):** `ShipConfig.privatise()`, shared components,
  existing attack patterns and bullet pools, the Drone Interceptor's orbit-and-dash tuning, the
  Space Station's modular boss structure, and the Bonus Drone must all keep working unchanged.
  Every existing Assault wave (all 264 path-driven spawns) must keep behaving identically.
- **Gate:** the project's existing invariant tests (config isolation, contact-damage,
  contact-hitbox and hurtbox geometry, player-bullet lifetime, signal arity, project load
  integrity, the space-station family) must stay green, and `bash /agent/verify.sh` must pass.
- **Class-name collisions:** `MovementController` was already taken by the player's input handler,
  forcing the `EnemyMover` rename (P-1).

## Open questions at the time, and how each was resolved

| Question | Resolution |
|---|---|
| Numeric layer allocation | No numeric value changed. Layers 3/5/6/11 gained names (fixing a typo on layer 3); bit 4 stays unnamed/unallocated; bit 12 (`area_control`, 2048) is reserved for Phase 6 (gravity wells). |
| Does `DamageReaction` replace `BaseEnemy`'s damage flow? | No, not in Phase 1 (P-15). The flows differ too much (AnimationPlayer flash vs. tween, no Shield support today, the station's delayed-death override) for the swap to be worth the churn now. Revisit in Phase 5, when enemies first need shields. `_on_received_damage`/`_on_health_changed` are documented virtual hooks instead. |
| Difficulty tiers | Deferred to Phase 16. Only the `accuracy` hook on `TargetInfo.aim_direction` (and the aimed/gatling patterns) exists this phase, defaulted to `0.0` everywhere so nothing plays differently today. |
| Roadmap phase count (17 vs. 18 vs. 19 vs. 20) | Resolved twice during review: 17 → 19 in round 1 (F7), and the board grew to 20 phases before round 2 closed (N4) — Phase 20 (late-system integration) was reconciled into the roadmap without needing a third review round, since the board is the source of truth (P-14) and no requirement was dropped. |
| Should the Assault constraint clamp position or filter velocity? | Velocity filter, chosen over a position clamp (which would teleport off-screen spawns) or transforming AI into camera space (which reintroduces the coupling the epic removes). |
| Drone Interceptor: `constraint_mode = AUTO` or `NONE` in Phase 1? | `NONE` (F4, option a) — keeps the port byte-identical to pre-rework Assault behaviour; Phase 2 (Razor Drone) turns the corridor on and re-pins. |
