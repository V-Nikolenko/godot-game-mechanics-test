# Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family — plan

Epic `cmufs7ekv000lnm2x7nbswijy`, plan task `cmufs7el6000tnm2xi4kud4v1`, 2026-09-28. Revision 1.

This plan builds on `1-context.md` (code facts, requirement ids `R3.1`–`R3.21`, risks `C1`–`C13`) and `2-research.md`
(scope check `S1`–`S12`, findings 1–8, options §2, starting values §3). Both are in this directory, and this plan does
not repeat them. It also builds on `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (the Phase 1 and Phase 2 plan
sections, the *Built in tX* notes and both *as built* sections) and on `docs/epics-done/cmufs7ek60001nm2x6d0bt2et/REPORT.md`.
Where this plan changes an earlier decision, §2.0 says so.

Values marked **[judgement]** have no citable source. They are starting defaults in `.tres` configs, so they can be
tuned without code changes. Values marked **[estimate]** were worked out by hand from scene and level data for this
plan. The task that owns each one must recompute it from live data in a test, as the Phase 2 t16 lesson requires. A
hand-computed number was wrong there. Symbols are cited rather than line numbers, because line numbers drift.

**Correction to `2-research.md` S10 / `1-context.md` C3 (verified in code for this plan).** In-flight enemy bullets
**cannot** hold an ENEMIES_CLEARED section open after their shooter is gone:
- `BulletPool._exit_tree()` calls `cancel_active()`, which `queue_free()`s every bullet in flight.
- `_recycle()` frees a returning bullet when its pool is being deleted.

So the container empties when the last *ship* leaves, and the deadline formula needs **no bullet-flight term**. The
research's proposed bar on firing Heavy Shells in ENEMIES_CLEARED sections is dropped. One consequence is a visible
side effect: when a fighter frees itself on DISENGAGE, its in-flight bullets vanish mid-screen. Legacy fighters
already did this when `free_after` fired, so it is not a regression. It is recorded under Risks.

---

## 1. Problem (player-facing)

Today the Light Assault Ship (106 of them in level 1) and the Interceptor fly fixed rails:
- a fighter slides across the screen in a straight line or an arc, firing on a fixed timer, then disappears;
- the Interceptor hoses a constant 11 shots/s stream at the player, with no rhythm and nothing to react to.

Neither exists in Open Space. The player cannot learn anything about them beyond "dodge the line".

After this phase:
- **The Fighter** flies like a pilot. It accelerates in, passes beside the player, fires a short burst and extends
  past. It then makes a visible wide turn and comes back for a second pass.
  - From far away it fires an aimed 3–5-round burst at where the player is *going*.
  - Up close it sprays a 5–7-round short-range burst along its nose.
  - It announces each burst with a yellow light.
  - Three fighters close from the player's left and right as a pincer, while a fourth comes head-on. When one dies,
    another takes its place.
- **The Gatling Interceptor** does not chase. It swings out to the player's side, and its light goes yellow as it
  spins up. It fires a single 8–12-round stream, goes quiet, swings over to the other flank, and repeats.
  - Two Gatlings together aim their streams to cross at the player's likely next position.
  - They always come from the **same** side, so moving away from them still works.
- **Enemy rounds read differently.** A red-pink Pulse bolt, small pink Scatter pellets, a thin fast Gatling streak,
  and a big slow Heavy Shell that the next phases can pick up.
- **In Assault,** level 1's fighters and interceptors appear at the same moments and places as before. Once they arrive
  they fight as squads inside the corridor, then leave in time for the level to move on.
- **In Open Space,** a fighter pair and a Gatling pair now patrol the hub alongside the Swarm and Razor patrols, clear
  of the planets and pickups.

---

## 2. Design

### 2.0 Changes to earlier decisions, stated explicitly

| # | Earlier decision | This phase | Why |
|---|---|---|---|
| X1 | Ph1 t10 note: "Phase 15's migration must decide who ticks fire on a rail" | **Phase 3 decides it for the Fighter and the Gatling Interceptor** (§2.8). When the AI is suspended on a rail, the brain hands its `AttackController` back to self-timed `_process` fire, using a pattern equivalent to the legacy weapon. Ph15 reuses this rule for the other shooters | Repointing `WaveBuilder.FIGHTER` and the interceptor puts brain-driven shooters on the station's reinforcement rails, and on level 1's rails until the migration. A suspended brain would leave them **silent** (S4, C2) |
| X2 | Ph2: "Idle profiles for other families stay in Ph14" | The Fighter and Gatling get the **minimum** idle: an `AnchorIdle` shared ring, with none of the Razor's bespoke legs. Richer idle stays Ph14 | R3.20 puts both enemies in the hub. Without idle they would attack from frame 0 wherever they spawn (S9) |
| X3 | Ph2: "Assault migration: only level 1's Kamikaze/Interceptor spawns go off rails" | Level 1's fighter and interceptor spawns also go off rails in Ph3. Every other level-1 spawn, and every station reinforcement, stays on rails until Ph15 | Scope text (R3.19) |
| X4 | Ph1: keep the `EnemyPathMover` `"AIStateMachine"` name lookup until Ph15 | **Kept.** Its only real subject (`light_assault_ship.tscn`'s state machine) is removed in t8, so `test_enemy_path_mover.gd` is repointed at a **test fixture** scene that has an `AIStateMachine` child | Honours the Ph1 decision with the least churn (S6) |
| X5 | Ph2 as built: "Phase 3 is the first to need `Steering.lead_target` / `break_contact`" | **Neither is built.** `lead_target` is `TargetInfo.aim_direction()` / `intercept()`, as the Ph1 plan already said. The fighter's post-pass extension is a hold-heading leg plus a `turn_toward` curve, not a break-contact. `break_contact` stays with the Sniper (Ph4) | No real caller (S2) |
| X6 | Ph2: `SquadController` is event-driven, with no clock | Unchanged. It gains **one field**, `convergence_point: Vector2` (`Vector2.INF` = unset). Only the LEAD writes it, and `_reassign()` clears it whenever the LEAD changes, the same rule as `attack_window_open` | Convergence needs one shared aim point (C8, §2.6). A field is not a clock |
| X7 | Ph1: forward fire is `Vector2.DOWN.rotated(ship.rotation)` | Forward fire, and `EnemyPathMover`'s facing, honour `BaseEnemy.sprite_forward_angle`, read duck-typed with default `PI/2`. **This is bit-identical for every current user** (§2.3) | Forward fire went backwards on nose-up art (C1, S3). The fix removes the constraint on sprite direction |
| X8 | Ph2 deadline formula: `last_wave_max_delay + engage + exit + 0.5 ≤ timeout` (every enemy treated as if spawned in the last wave) | For **fighters**, the deadline test also has a **per-entry** form: `entry_spawn_time + engage + worst_exit + 0.5 ≤ waves_complete_time + timeout`. The drone rows keep the conservative form | Conservatively, a fighter needs `engage + exit ≤ 8.7 s`. That forces a budget shorter than one full pass cycle. cloud_descent's fighters actually spawn about 4 s before its last wave (§2.9.3) |

### 2.1 Where things live and what they are called (C12)

Names are fixed now, because Godot rejects duplicate `class_name`s at load time.

| Thing | Path | Classes |
|---|---|---|
| Fighter | `git mv assault/scenes/enemies/light_assault_ship → assault/scenes/enemies/fighter`. `light_assault_ship.gd/.tscn` → `fighter.gd/.tscn`, plus a new `fighter_brain.gd`. `states/` is **deleted** in t8 | `Fighter extends BaseEnemy` (was `LightAssaultShip`), `FighterBrain extends EnemyBrain`, `FighterConfig` (**kept**: it already names this enemy's config; extended, still flat). `FighterApproachState` / `FighterStrafeExitState` are deleted |
| Gatling Interceptor | `git mv assault/scenes/enemies/interceptor → assault/scenes/enemies/gatling_interceptor`, files renamed to match, plus `gatling_interceptor_brain.gd` | `GatlingInterceptor` (was `Interceptor`), `GatlingInterceptorBrain`, `GatlingInterceptorConfig` (was `InterceptorConfig`) |
| WaveBuilder | `assault/scenes/systems/wave_builder.gd` | `FIGHTER` / `fighter()` keep their names and are repointed at the new path. `INTERCEPTOR` / `interceptor()` → `GATLING_INTERCEPTOR` / `gatling_interceptor()`, with every call site updated (level 1 ×2, station ×4). This follows the Razor precedent. **New:** `w_formation()` |
| Rounds | `assault/scenes/projectiles/enemy_bullet/rounds/` | `pulse_round.tscn`, `scatter_round.tscn`, `gatling_stream_round.tscn`, `heavy_shell.tscn`: inherited scenes of `enemy_bullet.tscn`, no new script. `EnemyRounds` (`enemy_rounds.gd`, `class_name EnemyRounds`): `const PULSE/SCATTER/GATLING_STREAM/HEAVY_SHELL` scene paths plus `static func pool_size_for(max_burst: int, round_lifetime: float, min_burst_period: float) -> int` |
| Burst helper | `global/enemy_ai/burst_clock.gd` | `BurstClock extends RefCounted` |
| Legacy look | `enemy_bullet.tscn` (orange) | **Unchanged.** Every legacy shooter (station, gunship, bomber, sniper) keeps its look. Recolouring them is Ph17's readability audit |

`AllyFighter` is unrelated and untouched. `level_2_waves.gd` keeps compiling because `fighter()` keeps its name.

### 2.2 The bullet family (R3.12, R3.13)

**Decision: one inherited scene per round** (research §2.2 option A, finding 8b). Each round overrides only its
`Visual`, its `HitBox/CollisionShape2D` shape, its `ProjectileLifetime` values, its default `speed` and `HitBox.damage`,
and its `z_index`. Layers stay 256/128, inherited. The pattern still sets speed and damage on every shot. The scene
defaults are what a later enemy gets if it picks a round and sets nothing.

| Round | Look (finding 6) | Default speed / damage | Hitbox | `max_time` / `max_distance` | z | Consumer this phase |
|---|---|---|---|---|---|---|
| **Pulse Round** | Elongated red-pink bolt, `Line2D` 14 × 3, `(1, 0.25, 0.45)`, round caps | 300 / 8 | capsule r 2, h 10 | 8 s / 1400 px | 0 | Fighter aimed burst; Fighter rail fallback |
| **Scatter Round** | Small pink pellet, `Line2D` 5 × 4, `(1, 0.35, 0.6)`. Always fired as a spray, never as a stray | 420 / 6 | circle r 2 | 2 s / **450 px** (short range) | 0 | Fighter forward burst |
| **Gatling Stream** | Thin short streak, `Line2D` 10 × 2, `(1, 0.2, 0.3)`, drawn on top | 240 / 4 | capsule r 1.5, h 8 | 8 s / 1400 px | +1 | Gatling Interceptor, both AI and rail |
| **Heavy Shell** | Large round, `Line2D` width 12 with round caps, bright core `(1, 0.55, 0.65)` over a dark rim (a second, wider `Line2D` behind it). Hitbox smaller than the visual | 160 / 20 | circle r 5 | 12 s / 1800 px | −1 | **None this phase.** First consumer Ph4 (Bomber/Ram) or Ph10 (Heavy Gunship). Recorded in DECISIONS |

- All visuals are code-free, scene-authored `Line2D`s, like `enemy_bullet.tscn` today. There is no texture, so
  `test_entity_sprite_transparency.gd` has nothing to check. No PixelLab allowance is spent on rounds. **[judgement]**
  lengths and colours.
- **`EnemyBullet.reset()` restores the scene's own speed and damage.** Today it resets `speed` to the literal 250 and
  never restores damage. A new `_authored_speed` / `_authored_damage` pair is captured in `_ready()`. `reset()` restores
  both, so a round keeps its identity between pool uses. The legacy scene's authored speed is 250, so legacy behaviour
  is unchanged.
- **Lifetime rule, generalised.** `test_enemy_bullet_lifetime.gd` today derives one `min_speed` for the shared scene.
  t2 turns it into a sweep over `EnemyRounds`' four scenes plus the two legacy scenes. For each round it asserts:
  - `max_distance / scene_speed ≤ max_time` (distance ends the bullet first, as today);
  - the range covers the round's use: at least 1280 px, except Scatter, whose ≤ 500 px *is* the design.
  - The regex over `light_assault_ship.gd`'s source is replaced by reading `FighterConfig` / `GatlingInterceptorConfig`
    fields. The file is renamed in t6/t7, and t8 removes the literal the regex matched.
- **Pools (C6)** are sized with `EnemyRounds.pool_size_for(max_burst, lifetime, min_period) = max_burst ×
  ceil(lifetime / min_period)`, where lifetime = `max_distance / speed`. Each shooter's test asserts
  `pool_size ≥ pool_size_for(...)`. Starting sizes **[estimate]**:
  - Fighter Pulse pool: 5 × ceil(4.7 / 2.5) = **10**;
  - Fighter Scatter pool: 7 × ceil(1.07 / 1.2) = **7**, rounded to **8**;
  - Gatling Stream pool: 12 × ceil(5.8 / 2.7) = **36**.
- **Heavy Shell** is proven by a firing test with a bare fixture shooter (`BulletPool` + `AimedAttackPattern`), not an
  enemy. It lands, deals 20, and expires by distance. An unused-but-tested round is the honest reading of "later
  enemies can pick a round" (S5, option b).

### 2.3 Patterns and `BurstClock` (research §2.1 option A)

**Bursts and streams are sequenced by the brain.** `AttackController` is **not changed**.

- **`BurstClock`** (`RefCounted`, no node, no `Timer`):
  - API: `start(count: int, gap: float)`, `advance(delta: float) -> int` (shots due this tick; the first shot is due
    immediately on the first advance), `is_running() -> bool`, `shots_fired: int`, `stop()`.
  - Time is accumulated `delta` with subtract-not-reset, the `AttackController` rule.
  - The brain calls `attack.fire_now()` once per shot due, so a burst's size is exact even on a long frame.
- **`AimedAttackPattern` gains:**
  - `spread_angle: float = 0.0`;
  - `var rng: RandomNumberGenerator = null` (not exported, set per instance). Jitter is drawn only when
    `spread_angle > 0`, from `rng` if set, else the global `randf` (legacy never has spread, so it is unaffected);
  - `var aim_point: Vector2 = Vector2.INF`. If finite, the shot aims at that point instead of asking `TargetInfo`.
- **`GatlingAttackPattern` gains** the same `rng` and `aim_point`. With `rng == null` it keeps the global `randf`
  exactly as today (legacy rail streams, and the station).
- **Nose-correct forward (X7, C1).** Both patterns' non-aimed branch becomes
  `Vector2.RIGHT.rotated(ship.rotation + _forward_angle(ship))`, where `_forward_angle` reads
  `ship.get("sprite_forward_angle")` and falls back to `PI/2`. For `PI/2` this equals `Vector2.DOWN.rotated(rotation)`
  exactly. `EnemyPathMover`'s facing becomes `vel.angle() - sprite_forward_angle` (same fallback). For `PI/2` that
  equals the legacy `atan2(-vel.x, vel.y)`. With this, the sprite may be authored nose-up or nose-down (S12).
- `spawn_offset` is today a fixed `(0, 10)`. It stays, because both new enemies are about 64 px and 10 px is inside
  the hull. Rotating it with the nose is Ph17 polish, noted under Out of scope.

### 2.4 Fighter (R3.1–R3.5)

**Scene** (`fighter.tscn`):
- root `Fighter`, `FighterBrain`, `EnemyMover` (`constraint_mode = AUTO`), `StateLight`, a `ContactProfile`
  defaulted by `BaseEnemy` to COLLISION (it does not ram, IDEAS §16);
- `AimedAttack`: `AttackController`, `driven_by_brain`, `enabled = false`, with pool `AimedPool` (Pulse, 10);
- `ForwardAttack`: `AttackController`, `driven_by_brain`, `enabled = false`, with pool `ForwardPool` (Scatter, 8);
- one `CircleShape2D` shared by the body, `HurtBox` and `ContactHitBox` (the geometry gates);
- no `AIStateMachine`.

Both patterns are **built per instance in `fighter.gd`** from flat config fields (the Razor precedent), and given the
brain's `rng`. `EnemyBrain.attack` holds `AimedAttack`; the brain gets a second reference, `forward_attack`.

**Root script rule (Ph2 t8b):** `Fighter._ready()` copies the config onto the brain *after* the brain's `_ready()`.
The brain builds its `EngagementBudget` and state on its **first tick**.

**Phases** (`FighterBrain.Phase`, with `phase_changed(new_phase: int)` and `enter_phase()` as the one transition path
and the test seam): `APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE`, then t12 appends
`IDLE, NOTICING, RETURNING`.

- **Heading reference `h`.** Open Space: the player's velocity direction when its speed exceeds 40 px/s, otherwise the
  player's `TargetInfo.facing`. Assault: `Vector2.UP` (scroll-forward) whenever `mover`'s constraint has a non-empty
  `inner_rect()`. So flank passes are **lateral runs across the corridor** (R3.5).
- **Pass side `s`** ∈ {−1, +1} (left/right of `h`) comes from the role (§2.5). A solo fighter takes the side it is
  already on for its first pass and **alternates** on each later pass.
- **APPROACH:** `Steering.intercept` with `clamped_lead_time(d, speed, 0.3, 0.8)`, curved by `turn_toward` at
  `turn_rate`. Hands over to RUN_IN inside `run_in_range` (700 px).
- **RUN_IN (offset pursuit, finding 3):** seek `P + perp(h) × s × pass_offset`, where `P` is the predicted player
  position and `pass_offset` is 160 px, curved by `turn_toward`. The LEAD's frontal pass uses `P + h × pass_offset`
  plus a small lateral bias of 60 px toward `s`, so it comes head-on without ramming. RUN_IN ends at the **closest
  approach**: the first tick on which the distance to the player grows.
- **EXTEND:** holds the heading for `extend_seconds` (0.6 s) or until 350 px from the player.
- **TURN:** `turn_toward` the next pass's start point at `turn_rate`, until the heading is within 20° of it. This is the
  visible wide turn, with radius `max_speed / turn_rate`.
- **REPOSITION:** seek the start point `player + (perp(h) × s' − h × 0.3).normalized() × standoff_radius`
  (`standoff_radius` 480 px). In Assault the point is clamped into `inner_rect()`. Then RUN_IN again. After `passes`
  (2) passes:
  - **Open Space:** a 1.5 s regroup at the standoff, then a new cycle. Open Space fighters keep fighting; the leash is
    Ph13.
  - **Assault:** DISENGAGE, or DISENGAGE earlier when the budget expires.
- **DISENGAGE (Assault):** exactly the Ph2 shape. `release_constraint()`, `max_speed = exit_speed`, seek 64 px past the
  nearest edge of `projectile_world_rect()` chosen on entry, and free once outside. It curves with `turn_toward`, which
  gives the "curved exits" of R3.5. Budget expiry never interrupts a burst: DISENGAGE waits for `BurstClock` to finish.

**Weapons (R3.3), by distance, never by a spawn property.**
- **Burst opportunities:**
  - (a) in RUN_IN, the first tick inside `fire_range` (520 px);
  - (b) in TURN, the tick on which the nose comes within `nose_cone_deg` (12°) of the player, while inside
    `fire_range`;
  - (c) at most one burst per pass leg.
- **The mode is chosen at the opportunity, from distance `d`, with hysteresis (C7):**
  - `d < forward_range` (300) → FORWARD;
  - `d ≥ forward_range + mode_hysteresis` (360) → AIMED;
  - in between → the last mode used (initially AIMED).
- The mode is **latched** for the whole burst. It is exposed as `weapon_mode` (read-only) and `weapon_mode_changed(mode:
  int)`, emitted only on a change.
- **Telegraph:** `StateLight` CHARGING for `burst_telegraph` (0.3 s), then ARMED while the `BurstClock` runs, then OFF.
  The aim is re-evaluated through the telegraph and locked when the burst starts.
- **AIMED:** `rng` 3–5 Pulse shots, gap 0.10 s, speed 300, damage 8, `accuracy` 0.7, `spread_angle` 0.035 rad (±2°).
- **FORWARD:** `rng` 5–7 Scatter shots, gap 0.05 s, speed 420 (the legacy forward speed), damage 6, along the nose
  (§2.3), `spread_angle` 0.13 rad (±7.5°). This is the short-range spray.
- Because opportunity (a) happens at about 520 px and (b) at the end of a turn, often at 200–350 px, **one fighter
  naturally uses both modes in a single run**. In Assault the corridor keeps distances short, so FORWARD is more
  common. That is "chosen by geometry" as research §2.5 describes.
- Rail-only: `aim_mode` stays on `FighterConfig` and on the spawn prop, but **only the rail fallback reads it** (§2.8).
  An AI fighter ignores it. A test pins exactly that.

**Config (`fighter_config.tres`; flat, `@export_group` Movement/Attack/Defense/Tactics/Scoring):**
- HP 60, contact 20, score 25 (legacy);
- `max_speed` 300, `acceleration` 700, `braking` 700, `turn_rate` 1.8 rad/s. Pinned: `turn_rate × max_speed ≤
  acceleration` (540 ≤ 700). The turn radius is ≈ 167 px, so the diameter of ≈ 333 px fits inside the corridor (C5);
- `run_in_range` 700, `pass_offset` 160, `extend_seconds` 0.6, `standoff_radius` 480, `passes` 2;
- the burst fields above, `engage_seconds` 6.0, `exit_speed` 520, `rear_standoff_radius` 560.

All **[judgement]**, starting from `2-research.md` §3.

### 2.5 Fighter squads: pincer, frontal pass, handoff (R3.4, R3.14, R3.15)

This reuses `SquadController` as it is (X6 adds nothing for fighters). `Fighter.squad` is the duck-typed slot. On its
first tick the brain calls `update_target` and then `join`. Every tick it reads `role_of(self)` and never caches it (Ph2
t4 note).

| Role | Behaviour | Fires? |
|---|---|---|
| LEAD | Frontal pass (§2.4). Opens `attack_window_open` on RUN_IN entry, but only while it still leads (Ph2 t8c rule) | yes |
| FLANK_LEFT / FLANK_RIGHT | Pincer: passes on `s = −1` / `+1`. It holds at its standoff start point until it sees the window open, answers each window **once** (`_answered_window`, Ph2 precedent), and goes anyway after `flank_wait_max` (2.0 s), so a flank whose lead is dead or slow still attacks | yes |
| REAR | **Dry pass** (finding 1: 3 shooters). It flies REPOSITION holds on a ring at `rear_standoff_radius`, spaced by `rear_index/rear_count` (existing API), and makes a pass every other cycle with weapons held and the light OFF | **no** |

- **Handoff (S8).** A `formation()` is already one squad (Ph2 t5), and `_reassign()` recomputes roles by distance on
  every join and leave. What Phase 3 adds is **fighter semantics** for the roles plus tests.
  - The IDEAS §17 example: 5 fighters (a W or V5) spawn, then F1 (a FLANK) dies. The closest REAR becomes that flank in
    the same call, and the formation contracts because the REAR ring re-spaces over fewer members.
  - A REAR promoted to FLANK is "one ship switches to the attack role".
  - A role change mid-pass takes effect at the next REPOSITION. `_pass_role` is taken on RUN_IN entry, like the Swarm's
    `_pass_role` on WINDUP.
- **No cross-over:** a regroup test asserts that no two members swap sides of the player when a role is reassigned
  (finding 8a).
- **Squads stay per family (C9).** A mixed squad is never authored. Level 1's loose fighter lines get their own ids,
  `&"w<n>f"` (§2.9).
- **`w_formation(count := 5, spread := 60.0, depth := 40.0)`** is added to `WaveBuilder`. It is a zig-zag, two V's side
  by side: slot `i` sits at x = `(i − (count−1)/2) × spread` and y = `depth` when `i` is odd, otherwise 0. It follows
  the existing helpers' `FormationResource` / `FormationSlot` shape and design units. No level uses it yet. It closes
  S7.

### 2.6 Gatling Interceptor (R3.6–R3.11)

**Scene** (`gatling_interceptor.tscn`):
- root, `GatlingInterceptorBrain`, `EnemyMover` (AUTO), `StateLight`;
- one `AttackController` (`driven_by_brain`, `enabled = false`) with a `BulletPool` (Gatling Stream, **36**);
- COLLISION contact.

The `GatlingAttackPattern` is built per instance, with the brain's `rng`, `aim_at_player = true` and `accuracy` 0.8.

**R3.9 settled (S1):** the Gatling **aims its streams at a predicted point**. Its *movement* is what keeps it side-on.
`interceptor/ENEMY.md` and `docs/enemy-roster.md` ("always fires forward") are corrected in t18.

**Phases** (`GatlingInterceptorBrain.Phase`, same `phase_changed` / `enter_phase` shape): `APPROACH, SWING_IN, SPIN_UP,
STREAM, COOLDOWN, REPOSITION, DISENGAGE`, then t12 appends `IDLE, NOTICING, RETURNING`.

- **Flank point `F`** = `player + perp(h) × side × preferred_range` (380 px), where `h` is the heading reference from §2.4.
  - **Assault (R3.11):** "the side of the arena is the flank reference". `side` = the half of `inner_rect()` that is
    **opposite the player's x**, so the Gatling sits in the wider open lane.
  - `F.y` = `player.y − 60`, slightly ahead, clamped into `inner_rect()`.
- **APPROACH:** intercept, curved, to within `preferred_range + 250`.
- **SWING_IN:** seek `F` with `turn_toward`. `StateLight` CHARGING **from here** (the research judgement: the visible
  telegraph lasts ≈ 0.5–0.75 s though the mechanical spin-up is 0.25 s). It hands over when within 60 px of `F` or after
  `swing_in_max` (1.5 s).
- **SPIN_UP (0.25 s):** brake to `stream_strafe_speed`.
- **STREAM:** a `BurstClock` for `rng` 8–12 rounds at `stream_interval` 0.09 s, so the stream lasts ≈ 0.72–1.08 s. The
  Gatling strafes (`Steering.strafe`) tangentially at `stream_strafe_speed` (140 px/s): it "moves through the flank
  while firing". Light ARMED. Every round aims at the predicted point (or `aim_point`, §2.6.1), with ±0.05 rad jitter
  from `rng`.
- **COOLDOWN (0.4 s):** light OFF, keeps drifting.
- **REPOSITION:** `side = −side`, then brake and `turn_toward` a swing to the new `F`, for 1.0–1.5 s from `rng`. Then
  SWING_IN again.
- **DISENGAGE:** the Ph2 shape. Budget expiry never interrupts STREAM.

The resulting rhythm is ≈ 0.25 + 0.9 + 0.4 + 1.25 ≈ 2.8 s per window, and the average rate drops from 11 to about
3.5 shots/s (R3.8).

**Config:**
- HP 70, contact 20, score 75 (legacy);
- `max_speed` 260, `acceleration` 600, `braking` 900, `turn_rate` 2.0. Pinned: 520 ≤ 600;
- `preferred_range` 380, `stream_strafe_speed` 140, `spin_up_seconds` 0.25, `stream_rounds_min/max` 8/12,
  `stream_interval` 0.09, `cooldown_seconds` 0.4, `reposition_min/max` 1.0/1.5;
- round speed 240, damage 4, `stream_spread` 0.05, `accuracy` 0.8;
- `engage_seconds` 7.0, `exit_speed` 520.

All **[judgement]** from research §3. **Gatlings stay out of ENEMIES_CLEARED sections**, and the deadline test gains a
boundary row, like the Razor's (§2.9.3).

#### 2.6.1 Convergence fire (R3.10, C8, findings 4, 5 and 7)

- **The pair** is a Gatling squad of ≥ 2. The LEAD opens `attack_window_open` on SPIN_UP entry and writes
  `squad.convergence_point` (X6): the predicted player position at `T = clamp(d / round_speed, 0.4, 0.8)` s.
- **Every FLANK answers each window once.** On seeing the window:
  - if it is within `1.5 × preferred_range` of the player, it enters SWING_IN toward its convergence flank point, with
    CHARGING on at the same moment, so the pair visibly charges together (finding 7);
  - otherwise it skips this window.
- **Same half-plane (finding 5).** The FLANK takes the LEAD's `side`, found by the cross-product sign of the LEAD's
  position against `h`; the LEAD node is found through `members()` / `role_of()`, so no new API is needed. Its flank
  point is rotated `convergence_bearing_offset_deg` (40°) toward `h` from the LEAD's. Both shooters are therefore on one
  side of the player, 40° apart, and the far side stays open.
- **Aim:** in STREAM, each shooter sets `pattern.aim_point = squad.convergence_point` rotated about the shooter by an
  independent `rng` error of ±3°. Rounds still get their ±0.05 jitter. When the window closes (lead change, or LEAD
  COOLDOWN), `aim_point` goes back to `Vector2.INF`.
- REARs in a Gatling squad hold at `preferred_range + 200` and do not fire.
- A solo Gatling (`squad == null`) or a squad of one never converges.

### 2.7 Readability and sprites (R3.16)

- **One gameplay light per state**, using `StateLight` (Ph2) and no hull recolouring:

  | Enemy | CHARGING (yellow) | ARMED (red) | OFF |
  |---|---|---|---|
  | Fighter | burst telegraph | burst | otherwise |
  | Gatling | SWING_IN + SPIN_UP | STREAM | otherwise |

  **COMMIT (white) is not used by either.** Ph2 reserved it for a committed real attack, and neither enemy has a
  commit/feint distinction.
- **Sprites:** two PixelLab sprites. Before generating, the art tasks invoke the `pixel-art-generation` skill (strict
  top-down, `view: "high top-down"`, `isometric: false`).
  - Fighter 64×64: a compact dart silhouette with a distinct cockpit, engines and twin wing guns.
  - Gatling 64×64 (72×72 allowed): a broader, side-heavy hull with a visible rotary cannon pod. Its silhouette must
    differ from the fighter's at a glance.
  - Both: a dark hull, a cool blue edge highlight, a red faction stripe, and no painted light (the `StateLight` is the
    light).
- Nose direction is free (X7). The art task sets `sprite_forward_angle` to match and moves `StateLight` onto the hull.
  The transparency gate applies (≤ 90 % opaque), and the fix is `./scripts/strip-sprite-bg.sh`.
- Until the art lands, t8/t10 keep the legacy textures (`assault.png`, `interceptor.png`) as placeholders, with
  `sprite_forward_angle = PI/2` (nose-down). They are not changed.

### 2.8 Rails: the fallback (X1, C2, S4)

`BaseEnemy.suspend_ai()` already calls the brain's `on_suspended()`. Both new brains override it:

1. `squad.leave(self)` and `StateLight` OFF;
2. `attack.driven_by_brain = false` and `attack.enabled = true`, so `AttackController._process` self-times;
3. install a **rail pattern** equivalent to today's weapon, on the round pools the scene already has:
   - **Fighter:** `aim_mode == "FORWARD"` → forward Pulse at 0.3 s, 420 px/s, damage 8. Otherwise → aimed Pulse at
     `config.fire_interval` (0.8 s), 250 px/s, damage 8, `accuracy` 0;
   - **Gatling:** a constant stream at 0.09 s, 220 px/s, damage 4, spread 0.08, global `randf` (the legacy
     `GatlingAttackPattern`), from the Gatling Stream pool.

The only change a player can see on rails is the new round visuals, which is intended: the rails are temporary, until
Ph15. `aim_mode` and `shoot_forward()` / `shoot_at_player()` are now **rail-only inputs**, recorded in DECISIONS for
Ph15.

The rail fallback lands **inside** t8 (Fighter) and t10 (Gatling), not in a later task. The moment `FIGHTER` points at
the AI scene, level 1's fighters (until the migration) and the station's TOP reinforcements are on rails. t1 adds a
pin that fails if a rail fighter or interceptor stops firing.

### 2.9 Assault level 1 migration (R3.19, C3, C4, S11)

#### 2.9.1 Pin first (t1)

`tests/integration/test_level1_fighter_spawns.gd` pins every fighter and interceptor entry from
`Level1Director._build_sections()` data, never from text, row by row:
- section, wave trigger, offset, delay, formation type and size, `aim_mode` prop, `free_after`, and whether `movement`
  is set.

It also pins, per section:
- the **legacy peak concurrent fighters**, from each entry's legacy lifetime (`free_after`, or the rail's on-screen
  time from its movement and speed; the helper already estimates this for drones);
- the **legacy peak shots per second** (aimed = 1/0.8, forward = 1/0.3, interceptor = 1/0.09, per alive shooter).

The counts come from data **[estimate from grep: 64 lines, 106 fighters + 2 interceptors; deep_space 18 lines,
planet_approach 19, cloud_descent 27]**, and the test asserts the computed values, not these.

t1 also adds `test_station_reinforcements.gd::test_rail_reinforcements_fire`: every TOP fighter and LEFT/RIGHT
interceptor fires at least one bullet within 2 s of spawning. This is green today on the legacy scenes, and it guards
X1.

#### 2.9.2 DURATION sections (t16): deep_space and planet_approach

- Every `b.fighter()` line loses `.move()` and `.free_after()`, and keeps `.at()`, `.formation()` and `.delay()`.
  `shoot_forward()` / `shoot_at_player()` are **stripped** (the pin records what was there). Loose lines are tagged
  `squad(&"w<n>f")`, where `n` is the wave's index in `raw_waves` (the Ph2 convention).
- deep_space's two interceptors → `gatling_interceptor()` with no `.move()`, `squad(&"w<n>g")`, so they are a
  convergence pair.
- **Density (C4) gates**, in `test_level1_fighter_spawns.gd`, computed from the shipped configs and
  `tests/helpers/level1_drone_concurrency.gd` (generalised to take a lifetime function per kind):
  - the **attack-capable peak** (first three per fighter squad, first two per Gatling squad) ≤ **1.5×** the legacy peak
    fighters;
  - the **all-alive peak** ≤ **2.0×**;
  - the **peak shots/s** (AI fighters: max burst / (burst gap × size + the minimum burst period ≈ 1.2 s); Gatling:
    12 / 2.8) ≤ **1.25×** the legacy peak shots/s.
  - **[judgement]** The ratios are tighter than the drones' 2.0/2.5, because shooters make more noise per body than
    rammers.
- **Pre-approved levers**, in order, to use only if a gate fails:
  1. Fighter `engage_seconds` 6.0 → 4.5;
  2. `passes` 2 → 1 in Assault (a new config field, `assault_passes`);
  3. split a formation of 5+ into two squads.

  Any other change needs the owner.

#### 2.9.3 cloud_descent (t17): the ENEMIES_CLEARED section

- The same edit for its 27 fighter lines. The last fighter wave is at 72 s (delays up to 0.8). The last wave overall is
  the drones at 76 s, so `waves_complete` fires at ≈ 76.8 s and the timeout is 10 s.
- **Deadline (X8)**, in `test_engagement_deadline.gd`:
  - per fighter entry: `spawn_time + engage_seconds + worst_exit + 0.5 ≤ waves_complete_time + enemies_cleared_timeout`;
  - **[estimate]** the 72.8 s V3: 72.8 + 6.0 + ≈ 3.0 + 0.5 = 82.3 ≤ 86.8.
  - There is **no bullet term** (see the correction at the top).
  - Boundary rows: a fighter moved into the 76 s wave fails the per-entry check (76.8 + 9.5 > 86.8), and a Gatling in
    any ENEMIES_CLEARED section fails (the Razor precedent).
  - `worst_exit` uses the Ph2 formula with the fighter's `exit_speed` and `acceleration`, plus the Ph2 honest residual
    for exiting from speed (≈ 0.5 s at 300 px/s).
- **Real run:** `tests/integration/test_level1_fighter_exit.gd`, the Ph2 `test_level1_drone_exit.gd` shape. It uses a
  real `WaveManager` loaded with cloud_descent's waves from 66 s onward, and a stationary, hurtbox-less player stub. It
  asserts the container empties within `enemies_cleared_timeout` of `waves_complete`, that every fighter leaves in
  DISENGAGE, and that none has an `EnemyPathMover`.

### 2.10 Open Space hub (R3.20, X2)

**Minimal idle (t12), per brain:** `IDLE` (the shared ring around `patrol_anchor`: angle = `phase_offset +
member_index × TAU / member_count + idle_speed × t`, radius `idle_radius` 150), `NOTICING` (a single `blink_once`,
facing the player), and `RETURNING`. This follows the Swarm's t8d shape exactly:
- `AnchorIdle`, the `patrol_anchor = Vector2.INF` sentinel, and the `start_engaged` test seam (every earlier test sets
  it);
- engagement recomputed every tick from distance and `AnchorIdle` state;
- RETURNING never interrupts a live burst or stream.
- `perceive_radius` ≥ `fire_range`, or the enemy would shoot before it notices: Fighter 540 / lose 900, Gatling 560 /
  lose 900 **[judgement]**.
- Assault skips idle.

**Spawn (t13), `SectorHub._spawn_patrol()`:**
- a fighter squad of 2 on `fighter_anchor_bearing_deg` (180);
- a Gatling squad of 2 on `gatling_anchor_bearing_deg` (0);
- both on a new `shooter_ring_radius` (1500), with shared anchors set before `add_child`, seeded from `patrol_seed`.

**[estimate]** clearances, where clearance = distance to the nearest interactable − `idle_radius` − `perceive_radius`:
- fighter at (−1500, 0): nearest `LoreLogFortunaManifest` (−700, 460), ≈ 923 px → 923 − 150 − 540 ≈ **233**;
- Gatling at (1500, 0): nearest `ShipBoostUpPickup` (730, −212), ≈ 799 px → 799 − 150 − 560 ≈ **89**.

That 89 is thin. **t13 computes the real numbers with the existing generic sweep** (every `MissionTrigger` / `PickupBase`
child plus the player spawn) and may move a bearing or the ring. It must not hand-pick one (the Ph2 t16 lesson).
`test_sector_hub_patrol.gd`'s child-count assertion becomes a per-group count, and its clearance sweep gains the two
new groups. Pools resolve to `EnemyContainer` (pool → ship → container); a hub test pins a Pulse landing there, as Ph2
did for the Razor.

### 2.11 Mode compatibility (R3.17)

Every behaviour spec runs in both harnesses through `test_enemy_dual_mode.gd`'s pattern:
- `use_parameters` on a **label**, with the harness built inside the body (the Ph1 t12 leak trap);
- `_tick()` re-integration for mover-owned bodies;
- a fixed `rng_seed`.

Curve and radius assertions are made in `open_space`, where no constraint filters velocity, as in Ph2 B2. The `assault`
cases assert the phase sequence, the corridor containment, the lateral pass and the cadence. Run
`scripts/check-test-leaks.sh` after every task that awaits.

---

## 3. Build sequence

Each step is one task in `tasks.json`, under the same key.

1. **`t1-pin`** (test): §2.9.1 level-1 fighter/interceptor pin, legacy peaks and shots/s, and the station rail-fire
   test. It runs first, because every later task edits what it pins.
2. **`t2-rounds`**: §2.2 four round scenes, `EnemyRounds`, `EnemyBullet.reset()` restoring the authored speed and
   damage, and the generalised lifetime sweep, plus the Heavy Shell fixture-shooter test.
3. **`t3-burst-patterns`**: §2.3 `BurstClock`, the pattern `rng` / `spread_angle` / `aim_point` fields, nose-correct
   forward fire, and `EnemyPathMover` facing, with a two-convention test.
4. **`t4-convergence-field`**: X6 `SquadController.convergence_point`, cleared on a LEAD change, with unit tests.
5. **`t5-w-formation`**: §2.5 `w_formation()` with a layout test.
6. **`t6-rename-fighter`**: §2.1 `git mv`, the class renames, every roster, the WaveBuilder path, and the
   `test_enemy_path_mover.gd` fixture (X4). **No behaviour change**: the t1 pin and every legacy test stay green.
7. **`t7-rename-gatling`**: the same for the interceptor, including the `gatling_interceptor()` call sites.
8. **`t8-fighter-run`**: §2.4 solo fighter (brain, scene, config, two weapons, distance selection, DISENGAGE), the §2.8
   Fighter rail fallback, `states/` deleted, and the dual-mode specs.
9. **`t9-fighter-squad`**: §2.5 roles, the pincer/frontal/dry REAR, window answering, and handoff/regroup tests through
   a real `WaveManager`.
10. **`t10-gatling-windows`**: §2.6 solo Gatling, the pressure windows, side-on movement, the §2.8 Gatling rail
    fallback, and the dual-mode specs.
11. **`t11-gatling-convergence`**: §2.6.1.
12. **`t12-shooter-idle`**: §2.10 minimal idle for both brains.
13. **`t13-hub-patrol`**: §2.10 hub spawn and the clearance sweep.
14. **`t14-art-fighter`**, **`t15-art-gatling`**: §2.7 sprites.
15. **`t16-level1-duration`**: §2.9.2.
16. **`t17-level1-cloud`**: §2.9.3.
17. **`t18-docs`**: `updating-project-docs`, both `ENEMY.md` files (the Gatling "fires forward" correction),
    `docs/enemy-roster.md`, `assault.md` / `global.md` / `PROJECT.md`, `docs/BULLET_POOL.md`, the CLAUDE.md gate
    paragraph (new gates: the round lifetime sweep, the fighter pin/density, the fighter deadline rows, the rail-fire
    test), DECISIONS *as built*, and the dossier.

**Dependencies:**
- Roots: t1, t2, t3, t4, t5.
- t6 after t1, because the pin must exist before anything moves. t7 after t6, because both edit the same rosters,
  `wave_builder.gd` and the station file.
- t8 needs t2, t3 and t6. t9 needs t8, t4 and t5 (the regroup test uses a W5).
- t10 needs t2, t3, t7 and t8 (the same rosters and `test_enemy_dual_mode.gd`; serial order is explicit). t11 needs
  t10 and t4.
- t12 needs t9 and t11 (it appends phases to both brains after their combat is final). t13 needs t12.
- t14 needs t9. t15 needs t11. Each edits its enemy's scene only after the combat work is done.
- t16 needs t1, t9 and t11. t17 needs t16.
- t18 needs everything.

---

## 4. Test plan

Boundary cases are in **bold**. "Dual" means the case runs in both harnesses.

| File (task) | Cases |
|---|---|
| `tests/integration/test_level1_fighter_spawns.gd` (t1; updated in t6/t7/t16/t17) | The pinned spawn list equals the live one, row by row, counted from data. Legacy peak fighters and peak shots/s per section equal their computed values. After t16/t17: `movement == null` and `free_after` unset for every fighter and Gatling; triggers, offsets, delays and formations unchanged; no `aim_mode` prop left in level 1. Density ratios ≤ 1.5 / 2.0 / 1.25. **A fighter line given `.move()` again fails. A 3rd Gatling added to deep_space's pair pushes shots/s over (verified once by hand)** |
| `test_station_reinforcements.gd` (t1; still green after t6–t10) | `test_rail_reinforcements_fire`: every TOP fighter and LEFT/RIGHT squad ship fires ≥ 1 bullet within 2 s. The interceptor half-extent is read from the scene, not a literal 37 (C13). **The rail fighter's shot direction for `aim_mode = "FORWARD"` lies along its travel** |
| `tests/integration/test_enemy_rounds.gd` (t2) | Every `EnemyRounds` scene is an `EnemyBullet` with HitBox 256/128, a `ProjectileLifetime` and the table's speed, damage and shape. `reset()` after a pattern changed its speed/damage restores the scene's values. **The Scatter Round expires at ≤ 450 px of travel; the Pulse is still alive at 1280 px.** Heavy Shell fired by a fixture shooter hits a player-hurtbox stub for 20 |
| `test_enemy_bullet_lifetime.gd` (t2, rewritten) | The per-round sweep `max_distance / speed ≤ max_time`, with the range floor. Speeds are read from configs, not by regex. **A synthetic round at 100 px/s with the shared 18 s / 2400 px fails** |
| `tests/unit/test_burst_clock.gd` (t3) | `start(4, 0.1)`: advancing by 0.05-step totals gives shot times 0, 0.1, 0.2, 0.3, then stops. **A single `advance(1.0)` returns exactly 4**, never more. `stop()` mid-burst. **`start(0, …)` fires nothing** |
| `test_attack_patterns_forward.gd` (t3) | The forward shot direction equals the actor's travel direction for `sprite_forward_angle` `PI/2` **and** `-PI/2`. **A ship with no `sprite_forward_angle` property gets the legacy `DOWN.rotated(rotation)`, bit-identical.** `aim_point` overrides `TargetInfo`. Seeded `rng` jitter is reproducible and within `±spread_angle`. `EnemyPathMover` facing is unchanged for `PI/2` (legacy equality over 8 headings) and correct for `-PI/2` |
| `test_squad_controller.gd` (t4, extended) | `convergence_point` starts `INF`, persists across non-LEAD joins, and **clears when the LEAD leaves or a closer member takes LEAD** |
| `test_wave_builder_formations.gd` (t5) | W5 slot offsets, the zig-zag rows, and the count; **`w_formation(1)` is a single slot at the origin** |
| `test_enemy_path_mover.gd` (t6) | The `AIStateMachine` lookup is pinned on the fixture scene |
| `tests/integration/test_fighter.gd` (t8) | Dual: the phase sequence APPROACH → RUN_IN → EXTEND → TURN → REPOSITION → RUN_IN (second pass). Open Space: closest approach in RUN_IN is within `pass_offset ± 40` px **on side `s`**; the TURN radius is within 15 % of `max_speed / turn_rate`; the fighter never overlaps the player hurtbox during a pass; a solo fighter's second pass is on the other side. Assault: the passes are lateral (the velocity x-component dominates in RUN_IN), and the fighter stays in the corridor until DISENGAGE. **Weapon selection:** the player at 250 px → FORWARD 5–7 Scatter shots along the nose; at 400 px → AIMED 3–5 Pulse shots; **at 330 px after an AIMED burst stays AIMED, and after a FORWARD burst stays FORWARD (hysteresis)**; the mode does not change mid-burst when the distance crosses the threshold; `weapon_mode_changed` emits only on a change. **`aim_mode = "FORWARD"` on an AI fighter changes nothing.** Cadence: the gap between shots is 0.10 / 0.05 s ± one physics tick; at most one burst per pass leg; CHARGING precedes every burst by 0.3 s. Budget: DISENGAGE at `engage_seconds`, **never mid-burst**. Rail: `suspend_ai()` → the controller self-times at 0.8 s (aimed) or 0.3 s (FORWARD). Pool sizes ≥ `pool_size_for`. Config pins `turn_rate × max_speed ≤ acceleration` |
| `tests/integration/test_fighter_squad.gd` (t9) | A real `WaveManager` spawns `fighter().formation(v_formation(3))`: roles LEAD + FLANK_L + FLANK_R. The flanks pass on opposite sides (the pincer); the LEAD's closest approach is from the front half-plane. **Killing the LEAD reassigns within the same call**; a W5 with a FLANK killed promotes the closest REAR; **no member crosses to the other side of the player during reassignment**; REARs fire 0 shots; a flank with no window attacks after `flank_wait_max`. Dual |
| `tests/integration/test_gatling_interceptor.gd` (t10) | Dual: the rhythm is CHARGING before SPIN_UP; SPIN_UP 0.25 s ± a tick with 0 shots; STREAM fires N ∈ [8, 12] shots at 0.09 s ± a tick; COOLDOWN 0.4 s with 0 shots; REPOSITION flips `side`; repeat. **Seeds giving N = 8 and N = 12 both occur across a seed sweep, and nothing is ever outside.** Side-on: during STREAM the angle between the Gatling-to-player line and `h` is within 90° ± 35°. Assault: the Gatling sits in the half of the corridor opposite the player's x. The stream aims at the predicted point (a moving player: the mean round direction leads the current position). **Budget expiry during STREAM waits for the stream to end.** Rail: a constant stream at 0.09 s. Pool ≥ `pool_size_for` (36) |
| `tests/integration/test_gatling_convergence.gd` (t11) | Squad of 2: both reach CHARGING within one tick of each other; both are on the **same** half-plane; the bearing separation is ≥ 30°; both aim lines pass within 48 px of `convergence_point`. **The LEAD dies mid-window: the point clears and the FLANK's `aim_point` resets to `INF`.** A solo Gatling never sets `aim_point` |
| `test_fighter.gd` / `test_gatling_interceptor.gd` (t12, extended) | Hub idle: no fire while IDLE; the ring spacing follows `member_index`; NOTICING → combat inside `perceive_radius`; RETURNING beyond `lose_radius`; **RETURNING never interrupts a burst/stream**. Assault starts in combat |
| `test_sector_hub_patrol.gd` (t13, extended) | Per-group composition; clearance for all four groups from the generic sweep; the seed is reproducible; a Pulse fired in the hub lands in `EnemyContainer`. **The sweep with a pickup moved inside a shooter's reach fails** |
| `test_engagement_deadline.gd` (t17, extended) | The per-entry fighter rows for cloud_descent. **A fighter in the 76 s wave fails; a Gatling in any ENEMIES_CLEARED section fails** |
| `tests/integration/test_level1_fighter_exit.gd` (t17) | The real `WaveManager` run: the container is empty within the timeout of `waves_complete`; every fighter leaves via DISENGAGE |
| Invariant gates (t6, t7, t8, t10, t14, t15) | Contact damage, contact geometry, hurtbox geometry, config isolation (neutral at 10), single writer (empty allowlist), signal arity, sprite transparency, UID integrity, project load integrity. All stay green, with the rosters renamed |

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| K1 | **Density** (C4). 106 rail fighters with 4–6 s lives become AI fighters that make second passes | The t1 pin plus the t16 ratios, with the levers fixed in advance. The gate cannot judge feel; a human playtest is listed as a known gap |
| K2 | **cloud_descent deadline**: its real-run margin was 1.6 s for drones in Ph2 | The per-entry formula, the real-run test, and lever 1 (engage 4.5 s) pre-approved |
| K3 | **Silent rail weapons** (X1) | The fallback ships inside t8/t10, and the t1 station fire test fails first |
| K4 | **Pool starvation** (C6) is silent (`acquire()` → null plus a warning) | `pool_size_for` pinned per shooter. The convergence test also counts shots fired against N |
| K5 | **Burst geometry never triggers FORWARD in Open Space** if turns end far away | The test places the player at 250 px deliberately. If play shows FORWARD is rare, tune `forward_range`, not the mechanism |
| K6 | **Bullets vanish when their shooter exits** (the correction at the top) | Existing legacy behaviour. Recorded; owner-bound lifetime (`persist_after_owner_death`) is Ph5 |
| K7 | **Rename churn** across about 15 files and 8 tests | Rename-only tasks (t6, t7) with no behaviour change, gated by the t1 pin. `git mv` keeps the `.uid` sidecars |
| K8 | **Fighters crowding the Swarm** in mixed waves (deep_space has both) | Squads are per family (C9); nothing arbitrates between squads. Accepted for this phase; cross-squad arbitration is Ph14 messaging |
| K9 | **The Gatling hub clearance is thin** (89 px estimated) | t13 computes it and may move the bearing or the ring |
| K10 | **Heavy Shell ships unused** | Deliberate (S5). Tested by a fixture. Its first consumer is recorded in DECISIONS |

---

## 6. Requirements coverage

| Req | Delivered by |
|---|---|
| R3.1 Fighter replaces the Light Assault Ship, 56–72 px | t6, t8, t14 |
| R3.2 Attack run (approach, pass, burst, wide turn, reposition, second pass; acceleration + turn radius) | t8 |
| R3.3 Aimed 3–5 predicted / forward 5–7 fast, chosen by distance | t3, t8 |
| R3.4 Pincer + frontal pass | t9 |
| R3.5 Assault: corridor, lateral runs, curved exits; formations only a start | t8, t9, t16 |
| R3.6 Gatling replaces the Interceptor, 56–72 px, suppression | t7, t10, t15 |
| R3.7 Side-on range, flank passes, brake, swing to the other side | t10 |
| R3.8 Pressure windows 0.25 / 8–12 / 0.4 / reposition | t3, t10 |
| R3.9 Forward vs aimed settled: aimed at a predicted point | t10, t18 (docs) |
| R3.10 Convergence fire | t4, t11 |
| R3.11 Assault flank = arena side | t10 |
| R3.12 Pulse, Scatter, Gatling Stream, Heavy Shell on pooled `EnemyBullet` + `ProjectileLifetime` | t2 |
| R3.13 Later enemies pick a round | t2 (`EnemyRounds`); Heavy Shell's consumer is later phase 4/10 |
| R3.14 Dynamic groups: role assignment, regroup on death | t9 (on Ph2 `SquadController`) |
| R3.15 V/W/wedge/line/diagonal/cluster as spawn layouts → roles | t5 (W), t9 (handoff tests); the others already exist (Ph2) |
| R3.16 Readability + sprites | t8/t10 (StateLight), t2 (round looks), t14, t15 |
| R3.17 Combat tests in both harnesses | t8, t9, t10, t11, t12 |
| R3.18 §41 Phase 2 items 3–4 | this whole epic |
| R3.19 Level-1 spawns migrated, timing preserved | t1, t16, t17 |
| R3.20 Hub ambient spawn | t12, t13 |
| R3.21 §43 checklist answerable | t18 (each `ENEMY.md` answers the checklist) |
| Squad messages §18 | later phase 14 |
| General idle profiles §18.5 | later phase 14 (the minimum is here, X2) |
| EncounterDirector §32, leash §33 | later phase 13 |
| Rockets §11.2 | later phase 5 |
| Energy weapons §11.3 | later phase 8 |
| `max_distance_from_owner`, `persist_after_owner_death` §12 | later phase 5 |
| Difficulty tiers §29 | later phase 16 (the `accuracy` and `max attackers` hooks exist) |
| Line of sight §28 | later phase 4 |
| Other level-1 enemies off rails; rail-free station reinforcements | later phase 15 (which reuses the X1 rule) |
| Enemy audio telegraphs | later phase 17 |
| Recolouring legacy enemy bullets | later phase 17 |

---

## 7. Out of scope

- Any enemy other than these two. The Gunship, Bomber, Sniper and Ram keep the legacy `enemy_bullet.tscn`.
- Taking station reinforcements off rails (Ph15). Level 2 (the scene is unreferenced; it only has to keep compiling).
- `BulletPool` container injection (Ph5). Rotating `spawn_offset` with the nose (Ph17 polish).
- Cross-squad arbitration or attacker caps across families (Ph14).
- Muzzle flashes, spin-up particles and SFX (Ph17). The `StateLight` is the only telegraph this phase.

## 8. Open questions for the owner (not blocking)

1. Do the density ratios (1.5 / 2.0 / 1.25) match the intended feel of level 1, or should level 1 get *harder* with this
   phase?
2. Should the Heavy Shell have a consumer sooner? For example, a rail Gunship using it would be a two-line change, but it
   would alter a Ph10 enemy early.
3. Recolour every legacy enemy bullet to the new palette now, or leave it for the Ph17 audit, as planned?
