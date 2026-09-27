VERDICT: CHANGES_REQUESTED

# Plan review, round 1: Enemy rework phase 2 (Swarm Drone, Razor Drone, squad roles)

Reviewed `3-plan.md` (rev 1), `1-context.md`, `2-research.md` and `tasks.json` against the code on `agent/auto-dev`
(HEAD `e3ee6ce`), plus CLAUDE.md, DECISIONS.md, the phase-1 plan and the phase-1 REPORT.

Overall the plan is strong. Scope matches the epic and every out-of-scope item has a phase and a reason. Reuse is
right: `DefenseProfile` shape, `boost()`, `AttackController.fire_now()`, `BulletPool`, `TargetInfo`, the dual harness.
The research has real tradeoffs and relevant sources. The rename-then-evolve split (t9/t10), completeness guards
first (t1), and the swap-under-rails step (t14) before rails-off (t15) are the right ordering. I checked these claims
against the code and they hold: the cull rect ignores `offset` (D6), `free_after()` is read only by `EnemyPathMover`,
the BulletPool grandparent rule holds (D4), and there is no enemy audio anywhere, so the audio exclusion is justified.

Four findings block approval. Two are mechanisms that would not work as written: the blast and the overshoot curve.
The other two are a behaviour that no task owns and an oversized task.

---

## Blocking

### B1: The EXPLOSIVE blast can never hit the player as designed, and its tests would not notice (t3, t8)

Checked `assault/scenes/enemies/base_enemy.gd:160-169`, `global/components/explosion_effect.gd:1-6, 41-51`,
`assault/scenes/enemies/bomber/bomb.gd` and plan §2.3.

- **It is freed with its owner.** §2.3 makes the blast "a child `HitBox` … created by the profile".
  - Both detonation triggers kill the owner in the same call. Contact runs `health.set_health(0)`. Death runs
    `BaseEnemy._on_health_changed`, which calls `queue_free()` right away.
  - So the blast is freed at the end of the frame it was enabled in, before any physics step can report an overlap.
  - `ExplosionEffect` exists because of exactly this problem: it re-homes its particles into `actor.get_parent()`.
  - The plan calls death-while-armed "the blast's real gameplay value", and that is the case that can never land.
- **It is not positioned at the drone.** `ContactProfile` is a plain `Node`. An `Area2D` under a non-CanvasItem
  parent does not inherit the drone's transform, so a child blast sits at the canvas origin.
- **A one-physics-frame window armed with `set_deferred` probably never gets stepped.**
  - Enabling in frame N applies at the deferred flush.
  - The counter in frame N+1's `_physics_process` then queues the disable, which also applies before the server step.
  - The plan pins arm-while-overlapping for `set_armed()` (C5) but not for the blast.
  - `bomb.gd`, the only precedent, keeps its blast on for 0.15 s.
- **The §4 cases cannot catch any of this.** "Blast active for exactly one physics frame" and "death while armed
  detonates" can pass on flags and on the `detonated` signal while the player never takes damage.

**Required:**
- `detonate()` spawns the blast into the owner's parent at `actor.global_position`, following
  `ExplosionEffect.explode()`.
- The blast owns its own lifetime: N ≥ 2 physics frames on an accumulated counter, never `create_timer`, then it
  frees itself.
- t3/t8 add an integration case with a real player `HurtBox`:
  - an armed drone killed within `blast_radius` lowers the player's health by `blast_damage` (outside i-frames);
  - an unarmed drone does not;
  - `check-test-leaks.sh` stays clean.

### B2: `EnemyMover.max_turn_rate` does not bend velocity, so neither overshoot curves (t8, t10)

Checked `global/enemy_ai/enemy_mover.gd:169` (velocity = `move_toward`) and `:182-185` (the `max_turn_rate` cap is
applied to `actor.rotation` only).

- **Swarm OVERSHOOT (§2.7)** keeps "requesting the burst direction at `max_speed` while `max_turn_rate` bends the
  heading back toward the player". With that code the drone flies dead straight while only its sprite turns.
- **Razor OVERSHOOT (§2.8)**, "the mover's `braking` and `max_turn_rate` bring it round", brakes to a stop and then
  accelerates back. That is a stop-and-return, not IDEAS §5.1's "overshoots and curves away".
- **Root cause:** the misreading comes from `1-context.md:90` ("a capped turn rate produces the arc").
- **Why the tests miss it:** the §4 overshoot cases only check the state sequence (OVERSHOOT, one more pass, REJOIN),
  so they pass on a straight line.

**Required:**
- Specify a brain-side turn: the requested direction rotates toward the player by at most `turn_rate·delta` per tick.
  The natural home is a pure `Steering.turn_toward(current_dir, desired_dir, max_rate, delta)` added in t2 with unit
  tests.
- Add a case to each drone's spec: during OVERSHOOT, the velocity heading turns toward the player monotonically, by
  no more than `turn_rate·delta` + ε per tick, while speed stays above a floor (it does not stop).

### B3: Nothing owns the Swarm Drone's hub idle (t8, t16)

Checked plan §2.7 (the state list includes `IDLE`/`NOTICING` "via `AnchorIdle` around the squad anchor"), §2.11,
the §2.7 config table and `tasks.json`.

- **No owning task.** t8 does not depend on t7 (`AnchorIdle`) and its description never mentions idle. t16 says only
  "The Swarm's hub idle uses AnchorIdle with squad.engaged". So the behaviour falls between the two tasks.
- **No config.** The Swarm config table has no `perceive_radius`, `lose_radius`, `notice_time` or idle-orbit
  radius/speed.
- **The spawn-safety proof covers only the Razor.** §2.11's "900 − 200 = 700 > 450" uses Razor numbers. A Swarm
  squad idling on a "REAR-style" orbit at `rear_orbit_radius` 260 would sit at about 640 px, and its perception
  radius is unstated.
- **No tests.** Nothing in §4 covers squad-wide engagement: one member perceives, `squad.engaged` latches, and every
  member leaves idle. Nothing covers the Swarm's handover or its return to idle either.
  - This is R2.16/R2.22 behaviour that can regress.
  - "Nobody perceives at frame 0" only proves the start state.

**Required:**
- Assign the Swarm idle to one task: t16, or a new task after t7 and t8. That task needs a `dependsOn` on t7.
- Add the config fields and values.
- Redo the spawn-geometry inequality with the Swarm's own radii.
- Add test cases:
  - one member inside `perceive_radius` → all members out of IDLE within one tick;
  - hysteresis;
  - return to anchor beyond `lose_radius`;
  - the handover velocity bound.

### B4: t8 is really three tasks (t8, and t9/t10 via dependencies)

Checked `tasks.json` t8 and plan §2.7, §2.9 and §4. t8 currently covers:
- a new shared component, `StateLight`, which t10 also needs;
- a new enemy (scene, config, `.tres`, ENEMY.md, gate rosters);
- a brain of about 10 states (APPROACH, FORM×3 roles, WINDUP, BURST, OVERSHOOT, second pass, REJOIN, DISENGAGE,
  rails);
- squad integration (roles, attack window, side claims);
- about 16 dual-mode cases, each run in two harnesses.

That cannot be finished and verified in one session, even on the escalated track. A failure there would also stall
t9 through t17.

**Required:** split it, for example:
- **t8a `StateLight`** (small): the component and its unit test.
- **t8b Swarm solo cycle** (large): the scene, config and rosters; APPROACH, WINDUP, BURST, OVERSHOOT, second pass,
  EXPLOSIVE contact, the Assault budget exit and rail suspension, all as a squad of one.
- **t8c Swarm squad behaviour** (medium or large): FORM roles, the flanks' attack window, side claims, lead
  reassignment mid-burst, formation recovery and phase offsets.

Then:
- t9 depends on t8b (the rosters);
- t10 depends on t8a;
- t15 and t16 depend on t8c.

---

## Non-blocking (fix in the revision, or record in DECISIONS as accepted)

- **N1: The "< 10 s" budget derivation (§2.6, t6/t8) leaves out the last wave's spawn delay.**
  - `LevelDirector._wait_enemies_cleared` starts its clock on `waves_complete`, which `WaveManager._process` emits
    when the last wave *triggers*.
  - Cloud_descent's last wave (`level_1_director.gd:985`) spawns its fifth drone 0.8 s later.
  - Worst case: 0.8 + 6.0 + 804/260 = 9.9 s, before the acceleration ramp or a retreat path that does not head
    straight for the nearest edge.
  - Missing the deadline only costs a `push_warning` and a forced free (the scoring is the same as escaping), but as
    written the test's own claim is false.
  - Fix: add the ENEMIES_CLEARED section's maximum last-wave delay plus a margin. Better: add one integration case
    that runs that wave under a real `ArenaCamera` and asserts the container empties before the timeout.
- **N2: The C3 escalation threshold is a coin toss, and t15 is the worst place to find out.**
  - A rough recount from `level_1_director.gd`'s triggers, delays and formation sizes gives legacy peaks (3.5 s
    lifetime) of about 12 / 6 / 5 in the three sections.
  - At about 9 s (6 s engagement plus exit), the peaks are about 23 / 9 / 10, a ratio of about 1.9, 1.5 and 2.0.
  - The numbers are deterministic from pinned data. Compute them in the plan now and decide in advance which lever t15
    may pull without escalating. For example: REAR members disengage early, or the budget is per role.
- **N3: `SquadController` API gaps (§2.4, t4).**
  - §2.4 and §2.7 rely on a member calling `leave()` on rail suspension, but the API block has no `leave()`.
  - Deciding FLANK_LEFT versus FLANK_RIGHT needs the player's heading, but the board holds only
    `target_position_hint`.
  - "Members hold the only strong reference" is false in Assault. For loose entries, t5 writes `"squad"` into dicts
    that stay in `WaveManager._waves` for the whole section. Either keep the board only in the per-spawn copy or
    correct the claim. The unit test's WeakRef case is unaffected either way.
- **N4: The phase-offset test (§4, t8) cannot fail on its own.**
  - "5 drones hold pairwise-distinct positions after 2 s" is already guaranteed by `rear_index × TAU / n` spacing and
    by separation.
  - Tests that give every drone the same `rng_seed` also give them identical rng phases.
  - Assert R2.3 directly: with separation off and distinct seeds, the drones' corkscrew/orbit phases differ.
- **N5: The feint geometry is underspecified (§2.8, t10).**
  - A lunge at `dash_speed × 0.5` = 240 px/s that brakes at 700 px/s² stops in about 41 px. It cannot "slide past" a
    player 130 px away.
  - The plan also does not say when WINDUP starts: before or after reaching the flipped anchor. Specify the lunge
    distance or duration and the WINDUP entry condition.
  - The "> 120° bearing change" test will force a choice anyway. Better to make it here.
- **N6: Tasks that share files have no ordering.**
  - t2 and t6 both edit `enemy_mover.gd`.
  - t5, t9 and t14 all edit `wave_builder.gd`.
  - This is harmless if the runner is serial on one branch, which the CLAUDE.md "no worktrees" rule implies. If tasks
    can run concurrently, add `t6 → t2` and `t9 → t5`.
- **N7: t9's acceptance grep catches `.claude/settings.local.json`**, which an agent must not edit. Exclude `.claude/`.
  Also, level 1 has 14 drone formations (cluster ×7, wedge ×6, line ×1), not 13 as `1-context.md` says; the t1
  recount will show it.
- **N8: `StateLight`'s texture is unspecified.** If it is scene-authored inside `assault/scenes/enemies/*`,
  `test_entity_sprite_transparency.gd` sweeps it, so a solid dot PNG would fail. Use a radial `GradientTexture2D`, or
  a PNG with transparent falloff.
- **N9: The "orbit centre inside `inner_rect()`" case (§4, t10) cannot fail with the player mid-screen.**
  `_visible_rect()` is the 1480×1480 square (`arena_camera.gd:108`). Place the player within `orbit_radius` of a
  corridor edge.
- **N10: The handover bound "Δv per tick ≤ acceleration·delta + ε" (t11) is mostly guaranteed by
  `EnemyMover.step()`'s `move_toward`.** It fails only on `halt()` or `boost()`. That is fine as a guard, but it should
  not be counted as proof of a "natural" transition. Also assert facing continuity (no rotation jump beyond
  `turn_lerp`).
- **N11: The hub ring (900 ± 200 px) sits near the mission planets** at 654–742 px (`sector_hub.tscn:58, 66, 74`).
  - An idle Razor can be about 200 px from a planet, well inside `perceive_radius` 450.
  - So fights will start during the mission-trigger dwell, which cancels above 150 px/s.
  - This is already Open Question 2. Put it on the t16 playtest checklist explicitly.
- **N12: The "no `PatrolDrone` in `res://`" sweep (t16) must be limited to `.gd`/`.tscn`/`.tres`.** `docs/**/*.md`
  legitimately names it.

## Checked and fine
- Scope, the out-of-scope table and phase attribution; no build-ahead into Ph3, 4, 13, 14 or 15.
- Single-writer compliance: the `SquadController` role board, `release_constraint()` as a field write, and the brains
  requesting only.
- Signal arity (`contact_made`, `detonated`, `role_changed`).
- UID handling (`git mv` keeps the sidecars).
- Configs: flat, and `privatise()` untouched.
- Design units versus world px.
- Invariant gate floors hold: a net 0 change in roster size.
- The Bonus Drone is untouched.
- The D4 pin.
- The corridor re-pin through the rename-then-evolve split.
- Dependencies t14 → t9 and t13 → t11.
- Complexities on the other tasks are reasonable. t3 as large is defensible because it touches the `BaseEnemy` hook
  for every enemy.
