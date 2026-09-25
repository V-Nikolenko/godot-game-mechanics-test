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

---

# Round 2 review

VERDICT: APPROVED

Scope of this pass: the revised `3-plan.md` and `tasks.json` and the idea's `DECISIONS.md`, as of commit `48b9399`, checked against the code on `agent/auto-dev`. All seven required findings (F1–F7) and the four optional ones (F8–F11) are resolved in the plan, the tasks and the decision log. I checked the numbers again myself; they are listed in the table.

The revision introduced no dependency cycle and no new file collision between tasks. It also introduced no contradiction between the plan, the tasks and `DECISIONS.md`.

What remains is below as N1–N7. Every one of them is either caught by an acceptance test the plan already requires, or it is limited to docs. None needs another re-plan. The implementer should apply N1–N3 as written, because each one corrects a statement in the plan or a task that is wrong as it stands.

## Round-1 findings

| # | Status | Evidence |
|---|---|---|
| F1 | Resolved | See F1 detail below. |
| F2 | Resolved | See F2 detail below. |
| F3 | Resolved | See F3 detail below. |
| F4 | Resolved | See F4 detail below. |
| F5 | Resolved | See F5 detail below. |
| F6 | Resolved | See F6 detail below. |
| F7 | Resolved for the 18-phase count. Since superseded: the board now has 20 phases. | See F7 detail below, and N4. |
| F8 | Resolved | `braking` and `max_turn_rate` (rad/s, 0 = off) are in 3-plan.md:172-181 and 188, and in t10 with unit tests. `expire_now()` stands for `explicit_destroy()` (3-plan.md:353-357). Distance is measured from the origin, and the plan gives the reason; owner distance goes to Phase 5 and player distance to Phase 13 (3-plan.md:605-609, §8 R5). |
| F9 | Resolved (see N3 for what is left) | The fix moved to t15 as a repo-wide sweep that cites symbols (3-plan.md:421-426; t15 description). t6 no longer touches it. |
| F10 | Resolved (see N2 for a spec conflict) | See F10 detail below. |
| F11 | Resolved | `EnemyBrain.actor` is typed `CharacterBody2D` (3-plan.md:122). `sprite_forward_angle` is read duck-typed, with a default of PI/2 (3-plan.md:183-186). t10 has a unit test for an actor that lacks the property. |

**F1: resolved.**
- Arming is lazy. It happens on `reset()` or on the first physics tick, and never in `_ready()` (3-plan.md:340-350; t13).
- The sniper shot is driven through the real `SniperEnemy._phase_fire()` and must be freed when it crosses the rect, well before 18 s (3-plan.md:399-402; t13 acceptance criteria).
- The "one frame past the muzzle" figure is right: 1400 / 60 ≈ 23 px, against a 126 px margin (2400 − 2274).

**F2: resolved.** I recomputed the numbers:
- The rect is x −164…1444 and y −444…1164, which is 1608 × 1608 px. Its diagonal is 2274.1 px.
- `min_speed = 150` comes from `station_gunnery.gd:70,75`, which I checked.
- `ceil(2274 / 150) + 2 = 18 s`, and `ceil_to_100(2338) = 2400`.
- The source table (3-plan.md:379-390) matches every `bullet_speed` and `speed` writer I found with a grep:
  - `gunship.gd:150`
  - `interceptor.gd:39`
  - `light_assault_ship.gd:42`
  - `racer_weapon.gd:26` together with the three racer states
  - the three patterns
  - `space_station_config.tres:21,26`
  - `enemy_sniper_bullet.tscn:19`
- The one writer the table leaves out is `reacher_aim_state.gd:11` (700). It is faster than the minimum, so it does not change the result.
- `DECISIONS.md` has been corrected to match.

**F3: resolved.**
- P-10 (3-plan.md:37) and §2.10 (3-plan.md:427-434) say that all three suspension steps run unconditionally.
- t10's description explicitly forbids the `if has_method … else` form.
- t2 adds a case on the real `light_assault_ship.tscn`, and t10 has to keep it green unchanged.
- I confirmed the mechanism in the code:
  - `light_assault_ship.tscn:111` has a node named `AIStateMachine`.
  - `state_machine.gd:16-18` ticks `process_physics` from `_process`.
  - `approach_state.gd:24-25` and `strafe_exit_state.gd:14-15` both call `move_and_slide()`.

**F4: resolved.**
- The plan takes option (a): the interceptor runs with `constraint_mode = NONE` (3-plan.md:455-458; t14; `DECISIONS.md`).
- §2.5 (3-plan.md:214-242) now covers what round 1 asked for:
  - it filters per axis;
  - speeds are in px/s;
  - it has four bands;
  - it states what "forced to re-enter" means;
  - it says the hard band does not apply until the enemy has entered.
- The band maths is continuous at d = 120, where both sides apply full pressure of 200 with the outward component scaled by 1. It is also continuous at d = 450, where the outward component is 0.
- The y ≈ −860 spawn figure checks out: 360 − 380 − 840 = −860, against a hard edge at −380 − 450 = −830.
- Every legacy cull bound (x −80…1360, y −80…800) lies inside `visible`.

**F5: resolved.**
- t6 now depends on t5.
- The new task t4b is the only first owner of `arena_camera.gd`. t11 depends on t4b, and t13 depends on t4b and never edits the file (3-plan.md:248-251 and 536-537; tasks.json).
- The `base_enemy.gd` chain is t1 → t5 → t6 → t10. The `arena_camera.gd` chain is t4b → t11.
- I found no remaining shared file between tasks that can run in parallel:
  - t8 edits the attack controller and the patterns.
  - t13 edits the enemy bullet.
  - t14 edits the drone and its config. It runs after t6 through the chain t14 → t12 → t11 → t10 → t6.
- The task graph has no cycle.

**F6: resolved.** Each factual error is corrected:
- P-2 now reads "two enemies plus the ally fighter" (3-plan.md:29).
- P-6 now uses the 2048 meaning (3-plan.md:33).
- The race has no separate wiring. `race_level_1.tscn:8,67` uses `arena_camera.gd` (3-plan.md:362-364).
- `level_2.tscn` is recorded as unreferenced, which I confirmed: only its own file mentions it (3-plan.md:365-367).
- The Open Space camera is correctly placed under `PlayerShip` (`sector_hub.tscn:83`; 3-plan.md:464-470).
- The station reinforcements never use the drone. I confirmed this in `test_station_reinforcements.gd:320-326`, and the only live spawns are `level_1_director.gd:290-291` (3-plan.md:471-474; t14 eyeball item).

**F7: resolved for the 18-phase count, since superseded.**
- §7 (3-plan.md:613-638) maps phases 1–19, and board phases 18 and 19 match rows 18 and 19.
- P-14 (3-plan.md:41) makes the board the source of truth for the phase count.
- The board now has **20** phases, though, and phase 20 is not mapped. See N4.

**F10: resolved.**
- There is a new invariant test, `test_enemy_mover_single_writer.gd` (3-plan.md:194-200; t10). N2 describes a conflict in its spec.
- t3 is now seed-robust: it checks the [1.0, 2.0] s window and the orbit by radius (3-plan.md:506-510; t3).
- t1's roster uses `<dir>/<dir>.tscn` with a `BaseEnemy` root, plus the turret (3-plan.md:495-500; t1).

## New findings (non-blocking; apply during implementation)

### N1 (medium). The sniper shot does not "inherit" the lifetime node. `3-plan.md:399-402`, P-12 (3-plan.md:39); task **t13-projectile-lifetime**

The plan says the sniper shot inherits the lifetime node. It cannot:
- `enemy_sniper_bullet.tscn:1-19` is a **standalone** scene. It has its own root node and only references `enemy_bullet.gd` as an `ext_resource`. It is not an inherited scene of `enemy_bullet.tscn`.
- `sniper_enemy.gd:32-33` preloads that scene.
- t13 only says to "add the node to enemy_bullet.tscn". Doing just that leaves the sniper shot with **no** lifetime rule once the constants at `enemy_bullet.gd:6-16` are deleted. Every sniper shot would then live until the level ends.

t13's required "sniper through the real `_phase_fire()` path is freed" criterion fails on that build, so the defect is caught rather than silent.

**Fix:** in t13, give `enemy_sniper_bullet.tscn` its own `ProjectileLifetime` node. Leave the `ext_resource` without a UID and do not copy one. Alternatively, have `EnemyBullet._ready()` add a default child when none exists, following the `DefenseProfile` pattern. Keep `reset()` null-safe in either case.

### N2 (medium). The single-writer sweep, as specified, flags `TargetInfo`, and `suspend_ai()` writes `velocity` itself. `3-plan.md:194-200, 274, 427`; `DECISIONS.md` "EnemyMover" bullet; task **t10-brain-mover**

The sweep covers every `global/enemy_ai/*.gd` except `enemy_mover.gd`, forbids any `velocity =`, and has an empty, permanent allowlist.
- `target_info.gd` sits in that directory. Its snapshot has a `velocity` member (3-plan.md:274), which it must assign in `of()` or its constructor.
- The sweep therefore goes red on t7's file the moment t10 adds it.
- `BaseEnemy.suspend_ai()` "zeroes `velocity`" (3-plan.md:427). That is a second velocity writer beside the mover. It escapes the sweep only because `base_enemy.gd` is not the root script of a swept scene. If the fixture enemy uses `base_enemy.gd` as its root script, the sweep flags it too.

t10 is a large task with its own plan and review, and the gate goes red immediately, so this will surface. The risk is that someone "fixes" it by renaming `TargetInfo.velocity` or by adding an allowlist entry.

**Fix, for t10's own plan:**
- In the `global/enemy_ai/` scripts and in brains, match only writes through a receiver: `actor.`, `_actor.` or `body.`, followed by `velocity` or `rotation`.
- In the root scripts of mover-driven scenes, which extend `CharacterBody2D`, match bare `velocity` and `rotation` writes.
- In all of these files, match `move_and_slide(`.
- Route `suspend_ai()`'s zeroing through the mover, for example with `mover.halt()`.
- Keep the allowlist empty.

### N3 (low–medium). t15's grep criterion cannot be met without rewriting historical and owner documents. Task **t15-docs**; `3-plan.md:421-426`

The criterion is: "`grep -rn "base_enemy.gd:[0-9]"` returns no hits", run over the whole repo. Today that grep also hits files that must not be rewritten:
- `docs/plans/**`, including this plan and this review;
- `docs/ideas/…/ENEMIES.md`, which is an attachment from the owner;
- `docs/enemy-rework/current-enemies.md`, which has about 25 hits and is an audit snapshot;
- `DECISIONS.md`, which is append-only.

The plan's list of known hits is also incomplete. It misses:
- `station_reinforcements.gd:128`
- `test_station_incoming_damage_paths.gd:17`

An implementer following the criterion literally would edit the owner's attachments and historical records.

**Fix:** scope the sweep to `assault/`, `global/`, `open_space/`, `tests/`, `docs/architecture/` and `tests/README.md`. Exclude `docs/plans/`, `docs/epics-done/`, `docs/ideas/` and `docs/enemy-rework/`.

### N4 (low; for the owner or harness to reconcile, not a defect in this phase). The roadmap maps 19 phases; the board now has 20. `3-plan.md:10, 41, 613, 706`; `DECISIONS.md:9`

Board phase 20 is "late-system integration — jammer-linked turret groups, difficulty tiers and checklist audit for the phase 18–19 behaviour". It has no row in §7.

No requirement is dropped:
- IDEAS §6.5's "connected to a jamming or power structure … disable the entire turret group" is covered through Ph8 (§6.5) and Ph9 (§6.6).
- The difficulty tiers are in Ph16.
- The checklist audit is in Ph17.

Phase 20 applies those phases to the output of Ph18 and Ph19. There is one real risk: a Ph9 implementer reading §7 could build linked turret groups that the board has placed in Ph20.

This does not block Phase 1. No Phase 1 task, interface or test depends on it, and P-14 already makes the board the source of truth. Revision 1 also went stale for the same reason: phases were added after the plan was written. Two reconciliations would close it:
- When t15 appends "Phase 1 - as built" to `DECISIONS.md`, it adds a roadmap line: "Ph20: §6.5 turret-group linkage to Ph9 jammers/power, Ph16 tiers and Ph17 checklist applied to Ph18–19 output; Ph8/Ph9 build the pieces, Ph20 links them."
- The owner corrects "19" in the plan header. Either one is enough.

### N5 (low). `ArenaCamera._ready()` returns early. `arena_camera.gd:61-64`; task **t4b-arena-provider**

`_ready()` returns early when there is no `Level1Background`. The group must be joined **before** that `return`, or a bare `ArenaCamera` is never a provider. t4b's unit test catches this: it asserts that an `ArenaCamera` in the tree is a provider. It is noted here so the first attempt is right.

### N6 (low). The rect edge in t13

Today's check expires only on `x > 1444` (`enemy_bullet.gd:33-34`). `Rect2.has_point()` excludes the right and bottom edges, so a `has_point`-based rule would expire a bullet at exactly x = 1444. The required boundary case catches this. The implementer should use explicit comparisons that reproduce `<` and `>`.

### N7 (low). A timing boundary in t3 and t14

Today, the dash velocity lands one frame *after* `_begin_dash()`: `drone_interceptor.gd:100-102` returns without setting velocity, and `:125-126` sets it on the next tick. Summing 1/60 in floating point can also add one more frame. The criterion "a dash by 2.0 s + 1 frame" can therefore be off by one on today's code.

**Fix:** allow two frames, or assert on the onset of `|velocity| == dash_speed` with a tolerance of ±2 frames. Both t3 and the port must use the same rule.

## Other checks that passed

- **Complexity** is appropriate throughout. t4b and t6 are small. t10 is large, so it is escalated with its own plan and review. The rest are medium.
- **Model assignments:** none are present in `tasks.json`.
- **Dependencies:** t15 depends on every leaf task, directly or transitively.
- **Behaviour preserved:**
  - `BulletPool._prewarm()` disables idle bullets through `process_mode` (`bullet_pool.gd:53`). An idle bullet's `ProjectileLifetime` child therefore never ticks, and it cannot emit `expired` while idle.
  - No enemy scene authors `HurtBox.accepted_damage_types`. Only the asteroid and race hazards do. So `DefenseProfile.apply_to()` writing the default empty list changes no enemy's behaviour.
- **Research and tradeoffs:** unchanged from round 1, and still adequate.
