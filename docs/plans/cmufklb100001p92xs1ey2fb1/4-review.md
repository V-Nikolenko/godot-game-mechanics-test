VERDICT: CHANGES_REQUESTED

Reviewer pass over `3-plan.md`, `1-context.md`, `2-research.md`, `tasks.json`, the idea folder and the code on
`agent/auto-dev` @ `fdce8cb`. The architecture holds up. Every claim below was checked in the source. Seven
items need fixing before hours of unattended implementation: three would cause silent regressions, and four
are plan or task-graph errors. None of them needs a redesign.

## What I verified and found correct

- Proposals sit at the top of the plan (§0, P-1…P-18), as the owner asked.
- `class_name MovementController` is taken (`assault/scenes/player/movement_controller.gd:1`), so the name
  `EnemyMover` is necessary.
- None of the new class names collide with an existing one: `TargetInfo`, `Steering`, `EnemyBrain`,
  `DefenseProfile`, `ProjectileLifetime`, `CollisionLayers`, `MovementConstraint`, `AssaultCorridorConstraint`
  and `DroneInterceptorBrain` are all free.
- `AttackController` is extended, not duplicated. It is a pattern plus a pool on a `_process` timer
  (`global/components/attack_controller.gd:24-30`).
- The mask rule is right, and it is subtler than the plan says. `base_enemy.gd:51` overwrites every
  scene-authored HurtBox mask. The scene values are 65 (bomber, gunship, kamikaze, light assault, bonus drone),
  97 (interceptor, drone interceptor, sniper) and 33 (ram). All of them become 1121 at runtime. Then
  `ram_ship.gd:21` sets 33 and `ram_ship.gd:45` sets 97. So "default profile = 1121, ram profile 33 → 97" is
  byte-identical at runtime.
- Only bits 1, 2, 3, 5, 6, 7, 8, 9, 10 and 11 are set in any `.tscn`/`.tres` outside `addons/`. That is
  exactly the set P-6 names, so the t4 invariant will be green.
- `ShipConfig` export groups are safe. `test_config_instance_isolation.gd:131-136` keeps only
  `PROPERTY_USAGE_STORAGE` fields, and group entries carry none.
- Rect arithmetic: `ArenaCamera` (640,360) ± (640,360) ± (100,380) gives x −100…1380 and y −380…1100. Adding 64
  gives `enemy_bullet.gd:13-16` exactly.
- Facing: `atan2(d.x, -d.y) == d.angle() + PI/2` and `atan2(-v.x, v.y) == v.angle() - PI/2`. So
  `rotation = heading.angle() - sprite_forward_angle` with ±PI/2 reproduces both conventions.
- `BulletPool.acquire()` sets `global_position` before `reset()` (`bullet_pool.gd:68-72`).
- `WaveManager` adds the entity (`wave_manager.gd:182`) before it adds the `EnemyPathMover` (`:198`). So
  `BaseEnemy._ready()` has already found its brain when `suspend_ai()` arrives.
- The research has real tradeoff tables and labels its judgement calls. Deferring `DamageReaction` and the
  `BulletPool` container, and pinning rather than fixing PatrolDrone, are all justified.

---

## Findings

### F1 (high). `ProjectileLifetime` as specified breaks the sniper shot. `3-plan.md` §2.9 (lines 286-304); task **t13-projectile-lifetime**

The plan records the origin and resolves the world rect only in `reset()`, and only `BulletPool.acquire()`
calls `reset()`. The sniper shot is unpooled.

`sniper_enemy.gd:99-103` builds it like this:
1. `instantiate()`
2. `set_direction`
3. `add_child`
4. then `global_position = _muzzle.global_position`

Nothing ever calls `reset()` on it. As written, a sniper shot in Assault therefore:
- never resolves `projectile_world_rect()`;
- measures `max_distance` from a default origin, not from the muzzle;
- lives up to `max_time` instead of expiring at x = 1444 and y = 1164 as it does today (`enemy_bullet.gd:31-37`).

The plan asserts the shot "inherits it and still frees". The mechanism for that is missing.

**Required:**
- `ProjectileLifetime` must arm itself lazily. It should record the origin and resolve the rect on its first
  physics tick after `_ready`, or on a `reset()`, whichever comes first.
- Alternatively, `sniper_enemy.gd` calls `reset()` after setting the position.
- In either case, the t13 case "the unpooled sniper shot is freed" must fire through the real
  `SniperEnemy._phase_fire()` path. It must place the shot where it crosses the legacy rect *before* 10 s, so
  a build that never resolves the rect fails.

### F2 (high). The `max_time = 10 s` derivation is wrong. `3-plan.md` §2.9 lines 299-301; tasks **t13**

The plan says the slowest enemy bullet is about 250 px/s. The shipped values are lower:

| Source | Speed |
|---|---|
| `space_station_config.tres:26` `core_bullet_speed` | **210** |
| `radial_attack_pattern.gd:41` default | 220 |
| `gatling_attack_pattern.gd:10` default | 220 |
| turret | 240 |

The rect diagonal is 2274 px, and 2274 / 210 = **10.8 s**, which is more than 10 s. The time rule *can* fire
inside today's rect, which contradicts the plan's claim. The t13 criterion "defaults cannot trip before the
rect for the slowest shipped enemy bullet speed; derived from shipped patterns and configs" will then fail.
The implementer will either have to change a number the plan fixed, or weaken the test.

**Required:**
- Fix the number: at least 11 s, or state the formula (`ceil(diag / min_speed) + margin`).
- Name every speed source the test must include:
  - pattern defaults;
  - `space_station_config` `core_bullet_speed` and `turret_bullet_speed`;
  - gunship `bullet_speed` (260);
  - racer speeds (300-360). `RacerWeapon` fires `EnemyBullet`.
- Put the corrected derivation in the plan and in `DECISIONS.md`, which currently repeats "10 s".

### F3 (high). The `suspend_ai()` "fallback" can switch off the name lookup for the light assault ship, and nothing pins it. `3-plan.md` §2.10 lines 324-327, P-10; tasks **t2-pin-path-mover**, **t10-brain-mover**

`LightAssaultShip` is a `BaseEnemy`, so after t10 it *has* `suspend_ai()`. Its `AIStateMachine` states call
`actor.velocity = …; actor.move_and_slide()`:
- `approach_state.gd:24-25`
- `strafe_exit_state.gd:14-15`

These run from `StateMachine._process`, which `set_physics_process(false)` does not stop. Only the name lookup
at `enemy_path_mover.gd:63-65` does.

The plan and t10 call that lookup the "fallback". An implementer who reads that literally writes
`if has_method("suspend_ai"): … else: <name lookup>`. That silently re-enables the state machine on every
path-driven light assault ship, and they are most of level 1's waves. The ship would fight the rail.

t2 pins suspension with "a minimal CharacterBody2D actor under tests/helpers/", which has no `suspend_ai()`.
So the pin cannot see this regression.

**Required:**
- State that the name lookup runs **unconditionally**, in addition to `suspend_ai()`. Alternatively,
  `BaseEnemy.suspend_ai()` itself disables a child `AIStateMachine`.
- Add a case to t2 or t10 that attaches an `EnemyPathMover` to the **real** `light_assault_ship.tscn` and
  asserts two things:
  - `AIStateMachine.process_mode == DISABLED`;
  - position equals the path sample after N frames.

### F4 (medium). The ported interceptor is not 1:1 in Assault, and the corridor spec has a gap. `3-plan.md` §2.5 (lines 187-207), §2.11, §1 "must play the same in Assault"; tasks **t11-corridor**, **t14-port-interceptor**

With `constraint_mode = AUTO`, the ported drone gets the corridor in level 1. Today it has none.

**Edge orbit.** The player is clamped to exactly the corridor's "visible" rect: `player_fighter.gd:99-100`
clamps x to −100…1380 and y to −380…1100. So orbiting a player at an edge, at radius 130, puts the drone up to
130 px into the band.
- Soft pressure then bends the orbit.
- 130 px is also *past* the 120 px soft band. §2.5 defines behaviour inside `soft` and at or beyond `hard`
  (450), but says nothing for the 120-450 px region. It also never gives the pressure's magnitude or units
  (px/s? a fraction of `max_speed`?).
- IDEAS §34 asks that an enemy be "forced to re-enter", and the plan's hard-band rule only removes outward
  velocity.

**Spawn beyond the hard band.** The spawn point is `cam.global_position + cam.offset + (±160, −420)·2`
(`wave_manager.gd:175`, `level_1_director.gd:290-291`). With the player at the top, `offset.y ≈ −380`, so
the spawn is at y ≈ −860, beyond the hard band (−830). The not-entered rule then strips ENTER's lateral
component until the drone latches.

The t3 pins cannot catch either effect, because they run with no `assault_arena` provider.

**Required. Pick one:**
- (a) The interceptor uses `constraint_mode = NONE` in Phase 1. That makes it truly 1:1. Its dash is already
  ended by the legacy cull, and every cull bound lies inside the corridor. Wire the corridor on it in Phase 2
  (Razor Drone).
- (b) Keep AUTO, list the edge-orbit and top-spawn deviations in §2.11 and `DECISIONS.md`, and pin them in the
  dual-mode test.

Either way, §2.5 must also define:
- the behaviour between `soft` and `hard`;
- the pressure units;
- what "forced to re-enter" means.

### F5 (medium). Task-graph collisions. **t5-defense-profile**, **t6-base-enemy-debt**, **t10-brain-mover**, **t11-corridor**, **t13-projectile-lifetime**

**t5 and t6 edit the same files with no ordering.** Both edit `base_enemy.gd`. Both also edit
`station_turret.gd`: t5 changes lines 34-35 to use the constants, and t6 fixes the comment at line 31.
- t6's stale-reference fix has to point at whatever t5 builds (the mask line it cites is the one t5 deletes).
- t10 also rewrites `base_enemy.gd`, and its chain (t10 → t6 → t1) never passes through t5.
- **Fix:** t6 depends on t5.

**t11 and t13 may both edit `arena_camera.gd`.** t13's description says "If t11 has not landed, add the
ArenaCamera provider here (whichever lands first owns it)", and neither task depends on the other. That is
conditional ownership of one file by two parallel-eligible tasks.
- **Fix:** give the provider to one task and make the other depend on it. The cleanest option is t13
  depends on t11.
- Also update §3's parallelism line, which lists t13 as independent.

### F6 (medium). Factual errors that will mislead the implementer and the human playtest

**§2.11 line 351 and t14's eyeball item.** They claim the station reinforcements spawn the drone interceptor
(`test_station_reinforcements.gd:325`). That test asserts the opposite: "drone_interceptor is self-managed AI
and must never get a mover". It checks that *no* squad uses it (lines 318-326). The only spawns are
`level_1_director.gd:290-291`. The playtest item should read "level 1's two drone interceptors" only.

**§2.9 and t13, "race: give it a provider".** `race_level_1.tscn:67-69` already *is* an `ArenaCamera`. Once
t11 adds the group, the race gets the legacy rect automatically, so no race-specific provider is needed. Keep
the race regression test.

The one Assault scene with a plain `Camera2D` is `level_2.tscn:10`. That scene is not referenced from
anywhere, so its bullets would fall back to time and distance only. Note it as accepted, or remove the dead
scene.

**§2.11 line 348, "Open Space: there is no cull today".** Open Space has a `Camera2D` under `PlayerShip`
(`sector_hub.tscn:83`). Today's `_check_off_screen` (`drone_interceptor.gd:129-140`) would cull against it.
`dash_max_distance` is still the better rule, but correct the rationale.

**P-2, "Three enemies and the ally fighter use it".** Only two enemies do: `light_assault_ship.gd:39` and
`interceptor.gd:36`. The third user is `ally_fighter.gd:40-46`, and it uses `ForwardAttackPattern`.

**P-6, "IDEAS §15 … gives 2048 the hazard meaning 1024 already has".** IDEAS gives 1024 "World hazards /
asteroid contact" and 2048 "Area-control / special hazards". That is a distinct meaning, and it is exactly
what the plan itself allocates in Phase 6. Only the 4096 boss-layer objection stands.

### F7 (medium). Roadmap phase count does not match the brief

The phase brief says the plan must carry "the full roadmap for all **18** phases". `3-plan.md` §7, P-14 and
`DECISIONS.md` all say 17, and claim "the chain is already on the board". Either:
- the board has 18 phase epics, in which case one is unmapped in §7 and §8; or
- the brief is wrong.

Reconcile it explicitly. Otherwise a board epic gets no scope from this roadmap, or the owner's count is
silently overridden.

### F8 (low). Scope items dropped without being listed as deviations

**IDEAS §3.1 `MovementController` fields.** The idea lists `turn_rate` and `braking`.
- The plan has `turn_lerp`, an exponential lerp factor, not a rad/s cap. That is fine for porting the
  interceptor, but it is not a turn rate.
- The plan has no braking at all.
- List both as deferred in §6/§8 with an owning phase, or add a `max_turn_rate` (0 = off).

**IDEAS §12.**
- `max_distance_from_owner` silently became "distance from origin".
- `explicit_destroy()` is not mentioned. Hits already emit `expired`, so it may be covered, but say so.
- Only `max_distance_from_player` is listed as deferred (R5 row, §8).

### F9 (low). Stale line references: the sweep is incomplete and runs too early. `3-plan.md` §2.10 line 322-323; task **t6**

Beyond the three references t6 names, these also cite `base_enemy.gd` line numbers:
- `space_station/ENEMY.md:350`
- `docs/architecture/modules/assault.md:420`
- `tests/README.md:330`
- `test_station_reinforcements.gd:372-373`
- `test_station_death_sequence.gd:58`

t5, t6 and t10 each renumber `base_enemy.gd` again. Move the fix to t15 as a
`grep -rn "base_enemy.gd:[0-9]"` sweep over the final file, or cite symbols instead of line numbers.

### F10 (low). Test-plan tightening

**t14 criterion "no direct rotation or velocity writes" (drone_interceptor.gd and its brain).** As written,
this is a review check, not a gate. Make it a source-sweep test in the style of
`test_ship_rotation_single_writer.gd`, scoped to mover-driven enemies. Otherwise the "EnemyMover is the single
writer" convention that `DECISIONS.md` and t15 put into PROJECT.md is unenforced.

**t3's "survive the port unchanged apart from setup".** t3 seeds the *global* RNG, and after the port the
draws come from `brain.rng`. Expected values survive only if the draw order and seed semantics match exactly.
Make t3's dash-onset assertion seed-robust instead: the dash begins within [1.0, 2.0] s of ORBIT entry, with a
boundary at each end.

**t1 sweep of `assault/scenes/enemies/*/*.tscn`.** It includes two scenes that are not `BaseEnemy` subclasses:
- `bomber/bomb.tscn`, which has no HurtBox;
- `space_station/station_turret.tscn`.

Specify the filter: `<dir>/<dir>.tscn` plus the root `is BaseEnemy`, with the turret as an explicit extra
case. That matches `test_config_instance_isolation.gd`'s sweep shape.

### F11 (low). `global/` code typed against an Assault class. `3-plan.md` §2.3 line 120, §2.4 line 175

P-13 forbids `global/` from importing `ArenaCamera`, yet two pieces of `global/enemy_ai/` depend on
`assault/`'s `BaseEnemy`:
- `EnemyBrain.actor: BaseEnemy`;
- `EnemyMover` reads `actor.sprite_forward_angle`.

There is precedent for this direction (`aimed_attack_pattern.gd:17` casts to `EnemyBullet`). Still, typing
`actor` as `CharacterBody2D` and reading `sprite_forward_angle` duck-typed costs nothing now, and it removes
work from Phase 15's `BaseEnemy` move. Note it either way.

---

## Required before approval

1. F1: `ProjectileLifetime` arms itself without a `reset()`, and the sniper shot is tested through the real
   fire path.
2. F2: correct the `max_time` derivation and number, and enumerate every speed source.
3. F3: the `AIStateMachine` name lookup runs unconditionally, and a real `light_assault_ship` + path-mover
   test is added.
4. F4: decide AUTO vs NONE for the interceptor's constraint in Phase 1, and complete §2.5's band spec.
5. F5: t6 depends on t5; t11 and t13 get a single owner for `arena_camera.gd`.
6. F6 and F7: fix the factual errors and reconcile 17 vs 18 phases.

F8 to F11 can be folded into the same revision.
