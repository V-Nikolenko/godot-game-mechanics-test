# Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family — plan

Epic `cmufs7ekv000lnm2x7nbswijy`, plan task `cmufs7el6000tnm2xi4kud4v1`. Revision 1: 2026-09-28. **Revision 2:
2026-09-29**, answering the owner's CHANGES_REQUESTED review (blocking B1–B6, should-fix 1–10). §9 *Response to
feedback* maps every point to the section that changed. The changed sections are §1, §2.0 (X6, X7, new X9), §2.2,
§2.3, §2.4, §2.5, §2.6, §2.6.1, §2.7, §2.8, §2.9, §3, §4 and §5.

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
  - In a squad, two fighters close from the player's left and right as a pincer while a third (the leader) comes
    head-on. Any further fighters wait their turn on a ring behind without firing. When one of the three dies, the
    nearest waiting fighter takes its place. (IDEAS §5.3 reads "three … pincer, while a fourth performs a frontal
    pass". This phase caps attackers at three, so the leader's frontal pass is one of the three. See §2.0 X9.)
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
| X4 | Ph1: keep the `EnemyPathMover` `"AIStateMachine"` name lookup until Ph15 | **Kept.** Its only real subject (`light_assault_ship.tscn`'s state machine) is removed in t8a, so `test_enemy_path_mover.gd` is repointed at a **test fixture** scene that has an `AIStateMachine` child | Honours the Ph1 decision with the least churn (S6) |
| X5 | Ph2 as built: "Phase 3 is the first to need `Steering.lead_target` / `break_contact`" | **Neither is built.** `lead_target` is `TargetInfo.aim_direction()` / `intercept()`, as the Ph1 plan already said. The fighter's post-pass extension is a hold-heading leg plus a `turn_toward` curve, not a break-contact. `break_contact` stays with the Sniper (Ph4) | No real caller (S2) |
| X6 | Ph2: `SquadController` is event-driven, with no clock | Unchanged in kind. It gains **two data fields** and no clock: `convergence_point: Vector2` (`Vector2.INF` = unset; the LEAD writes it every tick while its window is open) and `convergence_stage: Dictionary` (member → `0` answered / `1` ready in SPIN_UP / `2` stream done). `_reassign()` clears both whenever the LEAD changes, the same rule as `attack_window_open`. `leave()` erases the leaving member's key | Convergence needs one shared aim point and a bounded rendezvous for the pair (C8, §2.6.1, review B2). Fields are not a clock: each brain still times itself |
| X7 | Ph1: forward fire is `Vector2.DOWN.rotated(ship.rotation)` | Forward fire, and `EnemyPathMover`'s facing, honour `sprite_forward_angle`, read duck-typed with default `PI/2` through **one shared static helper**, `EnemyMover.sprite_forward_angle_of(node) -> float` (today's private `_sprite_forward_angle()` becomes a call to it). For `PI/2` the result equals the legacy value **within float epsilon, as an angle** (`angle_difference`), not bit-for-bit (§2.3) | Forward fire went backwards on nose-up art (C1, S3). The fix removes the constraint on sprite direction. One helper instead of three copies (review should-fix 2) |
| X8 | Ph2 deadline formula: `last_wave_max_delay + engage + exit + 0.5 < timeout` (every enemy treated as if spawned in the last wave) | For **fighters**, the deadline test also has a **per-entry** form (§2.9.3): `(entry_time − last_wave_trigger) + engage + deferral + worst_exit + 0.5 < timeout`, where `entry_time` = trigger + spawn delay + slot delay, and `deferral` is the longest attack the budget may not interrupt. The drone rows keep the conservative form | Conservatively, a fighter needs `engage + deferral + exit ≤ 9.5 s`. That forces a budget shorter than one full pass cycle. cloud_descent's fighters actually spawn at least 3.2 s before its last wave triggers (§2.9.3) |
| X9 | IDEAS §5.3: "three fighters … pincer, while a fourth performs a frontal pass" | **At most three fighters attack at once**: LEAD (frontal pass) + FLANK_LEFT + FLANK_RIGHT (the pincer). A fourth and later fighters are REARs that make dry passes and are promoted when an attacker dies | Research finding 1 (a three-attacker cap is what shipped games use for readable crowds) and the Ph2 attacker cap. Level 1 has formations of 3–6 fighters, and four simultaneous shooters per squad would break the density gates (§2.9.2) |

### 2.1 Where things live and what they are called (C12)

Names are fixed now, because Godot rejects duplicate `class_name`s at load time.

| Thing | Path | Classes |
|---|---|---|
| Fighter | `git mv assault/scenes/enemies/light_assault_ship → assault/scenes/enemies/fighter`. `light_assault_ship.gd/.tscn` → `fighter.gd/.tscn`, plus a new `fighter_brain.gd`. `states/` is **deleted** in t8a | `Fighter extends BaseEnemy` (was `LightAssaultShip`), `FighterBrain extends EnemyBrain`, `FighterConfig` (**kept**: it already names this enemy's config; extended, still flat). `FighterApproachState` / `FighterStrafeExitState` are deleted |
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
- **Lifetime rule, generalised, in three steps (review B5).** `test_enemy_bullet_lifetime.gd` today derives one
  `min_speed` for the shared scene, from `InterceptorConfig.new().bullet_speed` plus a regex over
  `light_assault_ship.gd`'s literals. The per-round check is **against the slowest speed any shooter fires that round
  at**, not the scene default, because the rail fallbacks fire Pulse at 250 and Gatling Stream at 220, below the
  Pulse scene's 300 (§2.8):
  - `max_distance / min_fired_speed ≤ max_time` (distance ends the bullet first, as today);
  - the range covers the round's use: at least 1280 px, except Scatter, whose ≤ 500 px *is* the design.
  - **t2** (no dependencies) adds the per-round sweep over `EnemyRounds`' four scenes plus the legacy scene. Its speed
    sources stay the ones that exist today: the regex and `InterceptorConfig`. A round with no shooter yet (all four at
    t2) is checked at its scene default speed.
  - **t6 / t7** (renames) only repoint the regex path and the config class name. They add no new logic.
  - **t8a** (the Fighter scene and rail fallback) replaces the regex with `FighterConfig` fields, including the rail
    speeds `rail_aimed_speed` (250) and `rail_forward_speed` (420), and maps them to the Pulse round. **t10** does the
    same for `GatlingInterceptorConfig` (`round_speed` 240, `rail_stream_speed` 220 → Gatling Stream). After t10 no
    speed in the sweep is typed by hand or read by regex. Each of those tasks' acceptance criteria names this.
- **Pools (C6)** are sized with `EnemyRounds.pool_size_for(max_burst, lifetime, min_period) = max_burst ×
  ceil(lifetime / min_period)`, where lifetime = `max_distance / speed`. A self-timed rail pattern is a "burst" of 1
  every `fire_interval`. **Each pool is sized to the larger of its AI need and its rail need (review should-fix 1)**,
  and each shooter's test asserts `pool_size ≥ pool_size_for(...)` for **both** cadences, with one exception below.
  Starting sizes **[estimate]**, recomputed by the test:
  - Fighter Pulse pool (`AimedPool`): AI 5 × ceil(4.67 / 2.5) = 10. Rail FORWARD 1 × ceil((1400 / 420 = 3.33) /
    0.3) = 12. Rail aimed 1 × ceil(5.6 / 0.8) = 7. **12.** (The legacy pool was 20.)
  - Fighter Scatter pool (`ForwardPool`): AI 7 × ceil(1.07 / 1.2) = **7**, rounded to **8**. No rail use.
  - Gatling Stream pool: AI 12 × ceil(5.83 / 2.7) = **36**. Rail need 1 × ceil(6.36 / 0.09) = 71. **The one
    exception:** the legacy Interceptor had a pool of 20 against the same 71, so on rails it has always fired about 20
    rounds and then stalled until rounds expired. The rail fallback **keeps that legacy shape**: 36 rounds, then a
    stall. It does not become a true 11 shots/s hose. A denser stream would make the station's LEFT/RIGHT
    reinforcements harder, which is a balance change this phase does not own. The test asserts `pool_size ≥ 36` (AI)
    and `≥ 20` (legacy rail), and **names the starvation as deliberate** in a comment. Ph15 takes the rails away.
- **Pool placement (review should-fix 3).** `BulletPool._ready()` resolves its container as
  `get_parent().get_parent()` (pool → ship → container). Every pool in this phase is therefore a **direct child of the
  enemy root**, never a child of an `AttackController`: `Fighter/AimedPool`, `Fighter/ForwardPool`,
  `GatlingInterceptor/StreamPool`. Each controller points at its pool through `bullet_pool`. A scene test asserts
  `pool.get_parent() == root` for every `BulletPool` in both scenes.
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
  `Vector2.RIGHT.rotated(ship.rotation + EnemyMover.sprite_forward_angle_of(ship))`. The new public static helper
  holds today's duck-typed read (`get(&"sprite_forward_angle")`, `float`/`int` accepted, else
  `DEFAULT_SPRITE_FORWARD_ANGLE` = `PI/2`), and `EnemyMover._sprite_forward_angle()` becomes a one-line call to it, so
  there is one copy. `EnemyPathMover`'s facing becomes `vel.angle() − sprite_forward_angle_of(actor)`.
- **Legacy equivalence is angular, not bitwise (review should-fix 2):**
  - `Vector2.RIGHT.rotated(r + PI/2)` equals `Vector2.DOWN.rotated(r)` only within float epsilon. Tests compare with
    `assert_almost_eq` on the components (tolerance `1e-5`).
  - `vel.angle() − PI/2` and the legacy `atan2(−vel.x, vel.y)` name **the same heading** but can differ by `2π`
    (e.g. `vel = (−1, −1)`: −5π/4 vs 3π/4). Tests compare with `absf(angle_difference(a, b)) < 1e-5`, as
    `test_enemy_path_mover.gd::test_facing_matches_the_nose_down_convention` already does. A rotation that differs by
    `2π` draws the same sprite, so no visible behaviour changes.
- With this, the sprite may be authored nose-up or nose-down (S12). **What `sprite_forward_angle` means (review
  should-fix 4):** the nose's direction in the **root's** local frame, measured *after* `BaseEnemy._rotate_sprite()`
  has flipped any child named `AnimatedSprite2D` by 180°. The legacy fighter texture is drawn nose-up inside an
  `AnimatedSprite2D`, and the flip makes it nose-down, so its value is `PI/2`. The legacy interceptor is a `Sprite2D`
  with no flip, drawn nose-down, so its value is also `PI/2`.
- `spawn_offset` is today a fixed `(0, 10)`. It stays, because both new enemies are about 64 px and 10 px is inside
  the hull. Rotating it with the nose is Ph17 polish, noted under Out of scope.

### 2.4 Fighter (R3.1–R3.5)

**Scene** (`fighter.tscn`):
- root `Fighter`, `FighterBrain`, `EnemyMover` (`constraint_mode = AUTO`), `StateLight`, a `ContactProfile`
  defaulted by `BaseEnemy` to COLLISION (it does not ram, IDEAS §16);
- `AimedAttack`: `AttackController`, `driven_by_brain`, `enabled = false`, whose `bullet_pool` is `AimedPool`
  (Pulse, 12, §2.2);
- `ForwardAttack`: `AttackController`, `driven_by_brain`, `enabled = false`, whose `bullet_pool` is `ForwardPool`
  (Scatter, 8);
- **both pools are direct children of the root** (§2.2, pool placement);
- one `CircleShape2D` shared by the body, `HurtBox` and `ContactHitBox` (the geometry gates);
- the legacy `AnimatedSprite2D` placeholder, kept until t14 (§2.7);
- no `AIStateMachine`.

Both patterns are **built per instance in `fighter.gd`** from flat config fields (the Razor precedent), and given the
brain's `rng`. `EnemyBrain.attack` holds `AimedAttack`; the brain gets a second reference, `forward_attack`.

**Root script rule (Ph2 t8b):** `Fighter._ready()` copies the config onto the brain *after* the brain's `_ready()`.
The brain builds its `EngagementBudget` and state on its **first tick**.

**Phases** (`FighterBrain.Phase`, with `phase_changed(new_phase: int)` and `enter_phase()` as the one transition path
and the test seam): `APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE`, then t12 appends
`IDLE, NOTICING, RETURNING`.

#### 2.4.1 Pass geometry (rewritten for review B1)

Revision 1 offset both the start point and the pass point along `perp(h)`. That made the run approach **laterally
toward the player's own side line** and left a closest approach of ≈ 67 px, a near-ram. Revision 2 defines a pass as
a **line parallel to the run direction, offset from the player by a fixed lane**, and starts the run **on that line**.
This is research finding 3's offset pursuit: the offset is perpendicular to the pursuer's line of approach, not to the
target's heading.

Conventions (Godot screen space, y down): for a unit vector `v`, `left(v) = v.rotated(−PI/2)` and
`right(v) = v.rotated(PI/2)`. Example: `v = UP (0, −1)` gives `left = (−1, 0)` and `right = (1, 0)`.

- **Heading reference `h`.** Open Space: the player's velocity direction when its speed exceeds 40 px/s, otherwise the
  player's `TargetInfo.facing`. Assault: `Vector2.UP` (scroll-forward) whenever `mover`'s constraint has a non-empty
  `inner_rect()`.
- **A pass** is three latched values:
  - the **bearing** `b`: the unit vector from the player to where the run starts. "Which side the fighter comes
    from."
  - the **run direction** `u = −b`;
  - the **lane vector** `l`: perpendicular to `u`. Its length is the lane distance, and its direction is "which side
    of the player the fighter passes on".
- **The pass line** is `P̂ + l + u·t`, where `P̂` is the predicted player position (`TargetInfo`, lead clamped to
  0.3–0.8 s), re-anchored every tick. `b`, `u` and `l` are latched on RUN_IN entry.
- **The start point** is `S = P̂ + b × standoff_radius + l`. `S` lies on the pass line, and the line's perpendicular
  distance from `P̂` is `|l|`, so **for a player holding course the closest approach is exactly `|l|`**.
- **What side means.** The old free parameter `s` is replaced by the pass kind, which fixes both sides explicitly:

  | Pass kind | Bearing `b` (side of approach) | Lane `l` (side of the pass) |
  |---|---|---|
  | FLANK_LEFT-shaped | `left(h)` | `h × pass_offset`: across the player's nose, **ahead** of it |
  | FLANK_RIGHT-shaped | `right(h)` | `h × (pass_offset + flank_lane_gap)`: ahead, one lane further out, so two flanks never share a line |
  | FRONTAL (LEAD) | `h` (starts ahead, comes head-on) | `right(h) × σ × pass_offset`, where `σ ∈ {−1, +1}` is the side of the player's heading line the LEAD passes on. It starts as `sign(right(h)·(X − P̂))` (0 → +1) and alternates on each pass |
  | Solo fighter | alternates FLANK_LEFT- and FLANK_RIGHT-shaped passes, both at lane `pass_offset`. The first pass matches the side it is on: `right(h)·(X − P̂) ≥ 0` → FLANK_RIGHT-shaped | as its kind |
  | REAR dry pass (§2.5) | FLANK-shaped on the side of its ring slot | `h × (pass_offset + 2 × flank_lane_gap)` |

- **Worked check** (`P̂ = (0, 0)`, `h = UP`, `pass_offset` 160, `flank_lane_gap` 100, `standoff_radius` 480). The test
  recomputes these:
  - FLANK_LEFT: `b = (−1, 0)`, `u = (1, 0)`, `l = (0, −160)`, `S = (−480, −160)`. The line is `y = −160`. The closest
    approach is at `(0, −160)`: **160 = `pass_offset`**.
  - FLANK_RIGHT: `b = (1, 0)`, `u = (−1, 0)`, `l = (0, −260)`, `S = (480, −260)`. The line is `y = −260`. Closest
    approach: **260 = `pass_offset + flank_lane_gap`**.
  - FRONTAL, `σ = +1`: `b = (0, −1)`, `u = (0, 1)`, `l = (160, 0)`, `S = (160, −480)`. The line is `x = 160`. Closest
    approach at `(160, 0)`: **160**.
  - Revision 1's formula for comparison: `S = (459.8, 137.9)`, pass point `(160, 0)`, a line ≈ 67 px from the player.
- **RUN_IN is path following, not point seeking.** Each tick the fighter projects itself onto the pass line and seeks
  the point `lookahead` (220 px) further along `u` from that projection, curved by `turn_toward`. The seek target is
  always ahead of the fighter, so RUN_IN **never stalls at a seek target**. A fighter that enters RUN_IN off the line
  (by up to `start_tolerance`, 80 px) converges long before the closest approach, because the run from `S` to the
  closest point is `standoff_radius` (480 px) long.
- **RUN_IN ends at the closest approach**: the first tick on which `(P̂ − X)·u < 0`, i.e. the player is behind the
  fighter along the run.
- **EXTEND:** holds the heading until the fighter is ≥ 350 px from the player, for at least 0.6 s and at most 1.5 s.
- **TURN:** `turn_toward` the next pass's `S` at `turn_rate`, until the heading is within 20° of the direction to `S`.
  This is the visible wide turn, radius `max_speed / turn_rate` (≈ 167 px).
- **REPOSITION:** seek the next pass's `S`, routed round the player. If the straight segment from the fighter to `S`
  would pass within `reposition_min_radius` (0.6 × `standoff_radius` = 288 px) of the player, the seek target is
  instead the ring point `P̂ + b_now.rotated(±min(90°, remaining)) × standoff_radius`, taking the shorter way round.
  Hand over to RUN_IN when within `start_tolerance` of `S` with the heading within 30° of `u`, or after
  `reposition_max` (3.0 s) from wherever it is. After `passes` (2) passes:
  - **Open Space:** a 1.5 s regroup at the standoff, then a new cycle. Open Space fighters keep fighting; the leash is
    Ph13.
  - **Assault:** DISENGAGE, or DISENGAGE earlier when the budget expires.
- **APPROACH:** `Steering.intercept` toward the **first pass's `S`** (not the player), with
  `clamped_lead_time(d, speed, 0.3, 0.8)`, curved by `turn_toward`. It hands over to RUN_IN on the REPOSITION
  criterion. If it gets inside `standoff_radius` of the player first, it hands over at once, with `b` recomputed from
  its current bearing as a FRONTAL-shaped pass, so it never ends up circling the player waiting.
- **Assault (R3.5):**
  - `S` and the lane are clamped into `inner_rect()`.
  - If the ahead lane does not fit (the player is within `|l|` + hull radius of the corridor's top), the lane flips
    behind the player (`l → −l`) for that pass.
  - If clamping leaves a flank run shorter than `min_run_length` (200 px), that pass takes the opposite bearing, so a
    fighter always has room to line up.
  - FLANK and solo passes are therefore **horizontal runs across the corridor** (lateral). The LEAD's frontal pass is a
    dive down one side of the player.
- **DISENGAGE (Assault):** exactly the Ph2 shape. `release_constraint()`, `max_speed = exit_speed`, seek 64 px past the
  nearest edge of `projectile_world_rect()` chosen on entry, and free once outside. It curves with `turn_toward`, which
  gives the "curved exits" of R3.5.
- **Budget expiry and deferral (review B4):**
  - Expiry in APPROACH, RUN_IN (no burst running), EXTEND, TURN or REPOSITION → DISENGAGE at once.
  - Expiry while a burst telegraph or `BurstClock` is running → DISENGAGE when the burst ends.
  - The **worst deferral** is `burst_telegraph + max(aimed_max × aimed_gap, forward_max × forward_gap)` =
    0.3 + max(5 × 0.10, 7 × 0.05) = **0.8 s**. (Counting `count × gap` rather than `(count − 1) × gap` is deliberately
    conservative.) The deadline formula carries this term (§2.9.3).

#### 2.4.2 Weapons (R3.3), by distance, never by a spawn property

- **Burst opportunities:**
  - (a) in RUN_IN, the first tick inside `fire_range` (520 px). A run starts at `|S − P̂|` ≈ 506 px, so this is
    usually the first tick of RUN_IN;
  - (b) in TURN, the tick on which the nose comes within `nose_cone_deg` (12°) of the player, while inside
    `fire_range`;
  - (c) at most one burst per pass leg.
- **The mode is chosen at the opportunity, from distance `d`, with hysteresis (C7):**
  - `d < forward_range` (300) → FORWARD;
  - `d ≥ forward_range + mode_hysteresis` (360) → AIMED;
  - in between → the last mode used (initially AIMED).
- **A FORWARD opportunity is taken only when the nose is within `nose_cone_deg` of the player.** Otherwise it is
  skipped and not spent. A forward spray fired while the lane holds the player 30°+ off the nose would never hit. In
  practice FORWARD comes from (b), and from (a) only on a frontal pass that started close.
- The mode is **latched** for the whole burst. It is exposed as `weapon_mode` (read-only) and
  `weapon_mode_changed(mode: int)`, emitted only on a change.
- **Telegraph:** `StateLight` CHARGING for `burst_telegraph` (0.3 s), then ARMED while the `BurstClock` runs, then OFF.
  The aim is re-evaluated through the telegraph and locked when the burst starts.
- **AIMED:** `rng` 3–5 Pulse shots, gap 0.10 s, speed 300, damage 8, `accuracy` 0.7, `spread_angle` 0.035 rad (±2°).
- **FORWARD:** `rng` 5–7 Scatter shots, gap 0.05 s, speed 420 (the legacy forward speed), damage 6, along the nose
  (§2.3), `spread_angle` 0.13 rad (±7.5°). This is the short-range spray.
- Opportunity (a) happens at about 500 px and (b) at the end of a turn, often at 200–350 px, so **one fighter naturally
  uses both modes in a single run**. In Assault the corridor keeps distances short, so FORWARD is more common. That is
  "chosen by geometry", as research §2.5 describes.
- Rail-only: `aim_mode` stays on `FighterConfig` and on the spawn prop, but **only the rail fallback reads it** (§2.8).
  An AI fighter ignores it. A test pins exactly that.

**Config (`fighter_config.tres`; flat, `@export_group` Movement/Attack/Defense/Tactics/Scoring/Rail):**
- HP 60, contact 20, score 25 (legacy);
- `max_speed` 300, `acceleration` 700, `braking` 700, `turn_rate` 1.8 rad/s. Pinned: `turn_rate × max_speed ≤
  acceleration` (540 ≤ 700). The turn radius is ≈ 167 px, so the diameter of ≈ 333 px fits inside the corridor (C5);
- geometry: `standoff_radius` 480, `pass_offset` 160, `flank_lane_gap` 100, `lookahead` 220, `start_tolerance` 80,
  `min_run_length` 200, `reposition_min_radius` 288, `reposition_max` 3.0, `passes` 2;
- weapons: `fire_range` 520, `forward_range` 300, `mode_hysteresis` 60, `nose_cone_deg` 12, `burst_telegraph` 0.3,
  `aimed_min/max` 3/5, `aimed_gap` 0.10, `aimed_speed` 300, `forward_min/max` 5/7, `forward_gap` 0.05,
  `forward_speed` 420, plus damage and spread;
- tactics: `engage_seconds` 6.0, `exit_speed` 520, `rear_standoff_radius` 560, `flank_wait_max` 2.0;
- rail (§2.8): `fire_interval` 0.8 (legacy), `rail_aimed_speed` 250, `rail_forward_speed` 420,
  `rail_forward_interval` 0.3, `bullet_damage` 8 (legacy), `aim_mode` (legacy).

All **[judgement]**, starting from `2-research.md` §3, except the legacy values. `test_config_instance_isolation.gd`
keeps the class flat.

### 2.5 Fighter squads: pincer, frontal pass, handoff (R3.4, R3.14, R3.15)

This reuses `SquadController` as it is (X6 adds nothing for fighters). `Fighter.squad` is the duck-typed slot. On its
first tick the brain calls `update_target` and then `join`. Every tick it reads `role_of(self)` and never caches it (Ph2
t4 note). The role picks the **pass kind** (§2.4.1).

| Role | Pass kind | Behaviour | Fires? |
|---|---|---|---|
| LEAD | FRONTAL | Opens `attack_window_open` on its RUN_IN entry, but only while it still leads (Ph2 t8c rule). **Closes it on its own EXTEND entry** (review should-fix 5). `_reassign()` also closes it on any LEAD change | yes |
| FLANK_LEFT / FLANK_RIGHT | FLANK_LEFT- / FLANK_RIGHT-shaped: the pincer, from the player's two sides, on two lanes | Flies to its `S` and loiters there (brakes to 60 px/s, nose along `u`). **Answers each window once**: on the first tick it sees `attack_window_open` with `_answered_window` false, it sets the flag and enters RUN_IN. The flag resets when it reads the window closed (the Swarm rule, `swarm_drone_brain.gd` `_answered_window`). If no window opens within `flank_wait_max` (2.0 s) of arriving at `S`, it goes anyway, so a flank whose lead is dead or slow still attacks | yes |
| REAR | REAR dry pass | **At most three attack (X9).** REARs hold a ring at `rear_standoff_radius`, spaced by `rear_index/rear_count` (existing API), and make a dry pass every other cycle, with weapons held and the light OFF | **no** |

- **Timing check for a V3** **[estimate]**. The flanks start when the LEAD's window opens, about 506 px out.
  - The LEAD crosses FLANK_RIGHT's lane (`y = −260`) after 220 px, at ≈ 0.73 s. FLANK_RIGHT reaches the LEAD's line
    (`x = 160`) after 320 px, at ≈ 1.07 s. That is ≈ 100 px apart.
  - FLANK_LEFT reaches `x = 160` at ≈ 2.1 s, long after the LEAD has gone.
  - t9 asserts a minimum body separation of 2 × hull radius between members over a full cycle. If that fails, the one
    pre-approved fix is a FLANK_RIGHT start delay, `flank_stagger` (0.4 s).
- **Handoff (S8).** A `formation()` is already one squad (Ph2 t5), and `_reassign()` recomputes roles by distance on
  every join and leave. What Phase 3 adds is **fighter semantics** for the roles plus tests.
  - The IDEAS §17 example: 5 fighters (a W or V5) spawn, then F1 (a FLANK) dies. The closest REAR becomes that flank in
    the same call, and the formation contracts because the REAR ring re-spaces over fewer members.
  - A REAR promoted to FLANK is "one ship switches to the attack role".
- **Side changes and the "no cross-over" rule (review should-fix 6).** `SquadController._side_for()` gives the second
  flank candidate the *other* flank role when both stand on the same side of the player. So a FLANK_LEFT may
  legitimately stand on the right, and it has to get round. The rule, which t9 asserts in these exact terms:
  1. **The pass is latched.** `_pass_role`, `b`, `u` and `l` are taken on RUN_IN entry and do not change until the
     next REPOSITION, whatever `role_of()` says meanwhile. A role change mid-pass takes effect at the next REPOSITION.
  2. **A member changes to a new pass kind only through REPOSITION**, and REPOSITION never seeks a target whose
     straight segment from the fighter passes within `reposition_min_radius` of the player (§2.4.1). This is asserted
     on the seek target every tick, not on an absolute side.
  3. A flank *run* crosses in front of the player by design (that is what a lateral pass is). Crossing during RUN_IN
     is not a violation.
- **Squads stay per family (C9).** A mixed squad is never authored. Level 1's loose fighter lines get their own ids,
  `&"w<n>f"` (§2.9).
- **W formation (review should-fix 8).** A new `WFormation extends FormationResource` in
  `global/resources/formation/w_formation.gd`, the same shape as `VFormation`, with `@export` `count` (5), `spread`
  (60), `depth` (40) and `stagger_delay` (0.1).
  - `compute_slots()`: slot `i` at x = `(i − (count − 1) / 2) × spread` and y = `−depth` when `i` is odd, otherwise 0.
    Odd slots trail, matching V's "behind = −y".
  - Delay: `stagger_delay × floor(|i − (count − 1) / 2|)`. For 5 slots that is 0.2 / 0.1 / 0 / 0.1 / 0.2: centre
    first, outwards like V's wing pairs.
  - `WaveBuilder.w_formation(count := 5, spread := 60.0, depth := 40.0, stagger := 0.1) -> WFormation` follows the
    other helpers. `w_formation(1)` is one slot at the origin with delay 0.
  - No level uses it yet. It closes S7.

### 2.6 Gatling Interceptor (R3.6–R3.11)

**Scene** (`gatling_interceptor.tscn`):
- root, `GatlingInterceptorBrain`, `EnemyMover` (AUTO), `StateLight`;
- one `AttackController` (`driven_by_brain`, `enabled = false`) whose `bullet_pool` is `StreamPool` (Gatling Stream,
  **36**, §2.2), a **direct child of the root**;
- COLLISION contact; the legacy `Sprite2D` placeholder until t15.

The `GatlingAttackPattern` is built per instance, with the brain's `rng`, `aim_at_player = true` and `accuracy` 0.8.

**R3.9 settled (S1):** the Gatling **aims its streams at a predicted point**. Its *movement* is what keeps it side-on.
`interceptor/ENEMY.md` and `docs/enemy-roster.md` ("always fires forward") are corrected in t18.

**Phases** (`GatlingInterceptorBrain.Phase`, same `phase_changed` / `enter_phase` shape): `APPROACH, SWING_IN, SPIN_UP,
STREAM, COOLDOWN, REPOSITION, DISENGAGE`, then t12 appends `IDLE, NOTICING, RETURNING`.

- **Flank point `F`** = `P̂ + right(h) × side × preferred_range` (380 px), `side ∈ {−1, +1}`, with `h` from §2.4.1.
  In Assault, `F.y` = `P̂.y − 60` (slightly ahead), and `F` is clamped into `inner_rect()`.
- **Which side, in which window (rewritten for review B3):**
  - **First window.** Open Space: the side it is already on, `sign(right(h)·(X − P̂))` (0 → +1). Assault (R3.11, "the
    side of the arena is the flank reference"): the half of `inner_rect()` **opposite the player's x**, i.e. the wider
    open lane.
  - **Every later window, both modes: REPOSITION flips `side`** (R3.7, "attacks from the other side"). The flip wins.
  - **The one Assault exception.** If the flipped `F`, after clamping into `inner_rect()`, would be closer than
    `min_flank_range` (220 px) horizontally to the player, the flip is skipped for that window and the Gatling stays on
    the open side. This happens when the player hugs a corridor wall.
  - So the "opposite half" assertion applies **only to the first window's SWING_IN target**. Later windows are
    asserted to alternate, except in the hugging-a-wall case.
- **APPROACH:** intercept, curved, to within `preferred_range + 250`.
- **SWING_IN:** seek `F` with `turn_toward`. `StateLight` CHARGING **from here** (the research judgement: the visible
  telegraph lasts ≈ 0.5–0.75 s though the mechanical spin-up is 0.25 s). It hands over when within 60 px of `F` or after
  `swing_in_max` (1.5 s).
  - **It never starts a window its budget cannot reach.** SWING_IN is entered only if the remaining budget is ≥
    `swing_in_max`. Otherwise the Gatling stays in REPOSITION/COOLDOWN until expiry. A CHARGING light is therefore
    always followed by a stream (the Swarm `can_start_attack` precedent).
- **SPIN_UP:** at least `spin_up_seconds` (0.25 s), braking to `stream_strafe_speed`. Light CHARGING. A squad pair may
  hold here up to `sync_wait_max` longer (§2.6.1); a solo Gatling never waits.
- **STREAM:** a `BurstClock` for `rng` 8–12 rounds at `stream_interval` 0.09 s, so the stream lasts ≈ 0.72–1.08 s. The
  Gatling strafes (`Steering.strafe`) tangentially at `stream_strafe_speed` (140 px/s): it "moves through the flank
  while firing". Light ARMED. Every round aims at the predicted point (or `aim_point`, §2.6.1), with ±0.05 rad jitter
  from `rng`.
- **COOLDOWN (0.4 s):** light OFF, keeps drifting.
- **REPOSITION:** flips `side` per the rule above, then brakes and `turn_toward`s a swing to the new `F`, for 1.0–1.5 s
  from `rng`. Then SWING_IN again.
- **DISENGAGE:** the Ph2 shape.
- **Budget expiry and deferral (review B4):** expiry in APPROACH, REPOSITION or COOLDOWN → DISENGAGE at once. Expiry in
  SWING_IN, SPIN_UP or STREAM → DISENGAGE on COOLDOWN entry. Because of the SWING_IN entry rule, the worst deferral
  after expiry is `spin_up_seconds + sync_wait_max + stream_rounds_max × stream_interval` = 0.25 + 0.75 + 12 × 0.09 =
  **2.08 s**, and the deadline boundary row carries it (§2.9.3).

The resulting rhythm is ≈ 0.25 + 0.9 + 0.4 + 1.25 ≈ 2.8 s per window, and the average rate drops from 11 to about
3.5 shots/s (R3.8).

**Config:**
- HP 70, contact 20, score 75 (legacy);
- `max_speed` 260, `acceleration` 600, `braking` 900, `turn_rate` 2.0. Pinned: 520 ≤ 600;
- `preferred_range` 380, `min_flank_range` 220, `stream_strafe_speed` 140, `swing_in_max` 1.5, `spin_up_seconds` 0.25,
  `sync_wait_max` 0.75, `stream_rounds_min/max` 8/12, `stream_interval` 0.09, `cooldown_seconds` 0.4,
  `reposition_min/max` 1.0/1.5;
- `round_speed` 240, `round_damage` 4, `stream_spread` 0.05, `accuracy` 0.8;
- convergence: `convergence_bearing_offset_deg` 40, `convergence_aim_error_deg` 3, `convergence_join_range_factor` 1.5;
- `engage_seconds` 7.0, `exit_speed` 520;
- rail (§2.8; the legacy `InterceptorConfig` fields, renamed where they were ambiguous): `rail_stream_interval` 0.09,
  `rail_stream_speed` 220, `rail_spread` 0.08, `rail_damage` 4.

All **[judgement]** from research §3, except the legacy values. **Gatlings stay out of ENEMIES_CLEARED sections**,
and the deadline test gains a boundary row, like the Razor's (§2.9.3).

#### 2.6.1 Convergence fire (R3.10, C8, findings 4, 5 and 7) — resequenced for review B2

Revision 1 opened the window only at the LEAD's SPIN_UP, while its light had already been CHARGING since SWING_IN, and
closed it on the LEAD's COOLDOWN. The FLANK could then reach STREAM after the window had closed, with no aim point.
Revision 2 opens the window at the **start** of the LEAD's telegraph, holds the pair at a bounded rendezvous, and closes
the window only after **both** streams have ended.

- **The pair** is a Gatling squad of ≥ 2: the LEAD plus its FLANKs. REARs hold at `preferred_range + 200` and never
  fire. A solo Gatling (`squad == null`) or a squad of one never converges.
- **Open (LEAD, SWING_IN entry).** The LEAD opens the window only while it still leads: it sets
  `attack_window_open = true` and `convergence_stage[lead] = 0`. From that tick, and **every tick until the window
  closes**, it writes `squad.convergence_point`: the player's position predicted `T = clamp(d / round_speed, 0.4, 0.8)`
  s ahead, where `d` is the LEAD's distance. The point is refreshed, never frozen, so a stream tracks a player who
  changes course.
- **Answer (FLANK, once per window).** A FLANK checks the squad on its own physics tick, so it sees the window at most
  one tick after the LEAD opened it.
  - Within `convergence_join_range_factor × preferred_range` (570 px) of the player: it sets its stage to 0 and enters
    SWING_IN toward its convergence flank point on the same tick, light CHARGING. **Both lights go CHARGING within one
    physics tick of each other** (finding 7: the pair visibly charges together).
  - Further away: it skips this window (no stage key) and keeps its own rhythm.
  - `_answered_window` resets when it reads the window closed, the Swarm rule.
- **Same half-plane (finding 5).** The FLANK takes the LEAD's `side`, found by the cross-product sign of the LEAD's
  position against `h`. The LEAD node is found through `members()` / `role_of()`, so no new API is needed. Its flank
  point is rotated `convergence_bearing_offset_deg` (40°) toward `h` from the LEAD's. Both shooters are on one side of
  the player, 40° apart, and the far side stays open.
- **Rendezvous (SPIN_UP).** On SPIN_UP entry a participant sets its stage to 1. It leaves SPIN_UP for STREAM when its
  own `spin_up_seconds` has passed **and** every key in `convergence_stage` is ≥ 1, **or** when `sync_wait_max`
  (0.75 s) has passed after its own spin-up, whichever comes first.
  - When both arrive within `sync_wait_max` of each other, both enter STREAM on the same frame, within one physics
    tick depending on processing order.
  - Both SWING_INs started within one tick and each lasts at most `swing_in_max`, so the worst gap is bounded. The
    wait is capped, and an early shooter never waits forever for a partner that died or got stuck.
- **Aim (STREAM).** Each participant sets `pattern.aim_point` every tick to `squad.convergence_point`, rotated about the
  shooter by an error of ±`convergence_aim_error_deg` (3°) drawn once per window from its own `rng`. Rounds still get
  their ±0.05 rad jitter.
- **Done (COOLDOWN entry).** A participant sets its stage to 2.
- **Close.** The LEAD closes the window on the first tick on which **every** key in `convergence_stage` is 2, i.e. at
  the **later** of the two COOLDOWN entries. Closing means `attack_window_open = false`, `convergence_point = INF` and
  the stage dictionary cleared. If the LEAD reaches COOLDOWN first, it keeps refreshing the point until the FLANK
  finishes. So **no participant ever streams without a point**.
- **Failure paths:**
  - A participant that leaves the squad (dies, or is suspended) is erased from `convergence_stage` by `leave()`, so it
    cannot hold the window open.
  - A LEAD change clears everything (`_reassign()`, X6). A FLANK that reads `convergence_point == INF` mid-STREAM sets
    `aim_point = INF` and **finishes its stream at its own predicted point**. The stream is not cut.
  - A FLANK whose remaining budget is below `swing_in_max` does not answer (the SWING_IN entry rule).
  - The LEAD never opens a new window while the last is still open. If it reaches its next SWING_IN first, it holds in
    REPOSITION until the close. That wait is at most `sync_wait_max` + one stream, about 1.8 s.

### 2.7 Readability and sprites (R3.16)

- **One gameplay light per state**, using `StateLight` (Ph2) and no hull recolouring:

  | Enemy | CHARGING (yellow) | ARMED (red) | OFF |
  |---|---|---|---|
  | Fighter | burst telegraph | burst | otherwise |
  | Gatling | SWING_IN + SPIN_UP (including the pair's rendezvous) | STREAM | otherwise |

  **COMMIT (white) is not used by either.** Ph2 reserved it for a committed real attack, and neither enemy has a
  commit/feint distinction.
- **Sprites:** two PixelLab sprites. Before generating, the art tasks invoke the `pixel-art-generation` skill (strict
  top-down, `view: "high top-down"`, `isometric: false`).
  - Fighter 64×64: a compact dart silhouette with a distinct cockpit, engines and twin wing guns.
  - Gatling 64×64 (72×72 allowed): a broader, side-heavy hull with a visible rotary cannon pod. Its silhouette must
    differ from the fighter's at a glance.
  - Both: a dark hull, a cool blue edge highlight, a red faction stripe, and no painted light (the `StateLight` is the
    light).
- **The sprite node and `BaseEnemy._rotate_sprite()` (review should-fix 4).** `_rotate_sprite()` flips any child
  **named** `AnimatedSprite2D` by 180°. Today:
  - the fighter's sprite is an `AnimatedSprite2D`, and its `HitFlashAnimationPlayer` tracks
    `AnimatedSprite2D:material:shader_parameter/enabled`;
  - `test_base_enemy.gd::test_animated_sprite_is_flipped_180_degrees` lists `light_assault_ship` (and `ram_ship`);
  - `test_enemies_without_an_animated_sprite_are_unaffected_by_the_flip` asserts that every other enemy has none;
  - the Gatling's sprite is a plain `Sprite2D` (no flip).

  **Decision:** each art task keeps its enemy's **node type and name**. The fighter keeps a single-frame
  `AnimatedSprite2D`, which is flipped; the Gatling keeps its `Sprite2D`, which is not. Then no animation track path
  and no `test_base_enemy.gd` list changes. `sprite_forward_angle` is set to the nose direction **as seen in the root's
  frame after the flip** (§2.3). For the fighter, a nose-up PNG becomes nose-down after the flip, so the value is
  `PI/2`. If an art task has to change a node type, it must also:
  - update the `HitFlashAnimationPlayer` track paths;
  - move the enemy in `test_base_enemy.gd`'s flip list (`light_assault_ship` becomes `fighter` in t6);
  - re-derive `sprite_forward_angle`.

  Its acceptance criteria say so.
- Nose direction is free (X7). The art task moves `StateLight` onto the hull. The transparency gate applies (≤ 90 %
  opaque), and the fix is `./scripts/strip-sprite-bg.sh`. A forward-fire test on the real scene proves the nose
  (§4, t14/t15 rows).
- Until the art lands, t8a/t10 keep the legacy textures (`assault.png`, `interceptor.png`) as placeholders, with
  `sprite_forward_angle = PI/2` (nose-down). They are not changed.

### 2.8 Rails: the fallback (X1, C2, S4)

`BaseEnemy.suspend_ai()` already calls the brain's `on_suspended()`. Both new brains override it:

1. `squad.leave(self)` and `StateLight` OFF;
2. `attack.driven_by_brain = false` and `attack.enabled = true`, so `AttackController._process` self-times;
3. install a **rail pattern** equivalent to today's weapon, on the round pools the scene already has, **from config
   fields** (§2.4.2, §2.6), so the lifetime sweep can read them (review B5):
   - **Fighter:** `aim_mode == "FORWARD"` → forward Pulse every `rail_forward_interval` (0.3 s) at
     `rail_forward_speed` (420), damage `bullet_damage` (8), from `AimedPool`. Otherwise → aimed Pulse every
     `fire_interval` (0.8 s) at `rail_aimed_speed` (250), damage 8, `accuracy` 0, from `AimedPool`. `AimedPool` (12)
     covers the FORWARD rail need of 12 (§2.2).
   - **Gatling:** a constant stream every `rail_stream_interval` (0.09 s) at `rail_stream_speed` (220), damage 4, spread
     `rail_spread` (0.08), global `randf` (the legacy `GatlingAttackPattern`), from `StreamPool`.

**What a player can see change on rails:**
- the new round visuals, which is intended;
- the rail Gatling stalls after 36 rounds in flight instead of the legacy 20 (§2.2, the deliberate exception).

The rails are temporary, until Ph15. `aim_mode` and `shoot_forward()` / `shoot_at_player()` are now **rail-only
inputs**, recorded in DECISIONS for Ph15.

The rail fallback lands **inside** t8a (Fighter) and t10 (Gatling), not in a later task. The moment `FIGHTER` points at
the AI scene, level 1's fighters (until the migration) and the station's TOP reinforcements are on rails. t1 adds a
pin that fails if a rail fighter or interceptor stops firing.

### 2.9 Assault level 1 migration (R3.19, C3, C4, S11)

#### 2.9.1 Pin first (t1), with frozen legacy baselines (review B6)

`tests/integration/test_level1_fighter_spawns.gd` pins every fighter and interceptor entry from
`Level1Director._build_sections()` data, never from text, row by row:
- section, wave trigger, offset, delay, formation type and size, `aim_mode` prop, `free_after`, and whether `movement`
  is set.

**The legacy baselines are frozen as constants**, the Ph2 `_EXPECTED_LEGACY_PEAKS` shape, because t16/t17 delete their
inputs (`.move()` and `.free_after()`):
- `_LEGACY_PEAK_FIGHTERS: Dictionary` (section → int). The peak concurrent fighters and interceptors, from each entry's
  legacy lifetime:
  - `free_after` when set;
  - otherwise the rail's on-screen time, from sampling its `MovementResource` (× `WORLD_SCALE`, from its spawn offset,
    with any player-focused movement aimed at the camera centre) until it leaves the legacy
    `ArenaCamera.enemy_cull_rect()`, capped at 20 s.
- `_LEGACY_PEAK_SHOTS_PER_S: Dictionary` (section → float). Per alive shooter: aimed = 1/0.8, forward = 1/0.3,
  interceptor = 1/0.09.
- While the rails exist, t1 **computes both from the live data and asserts they equal the constants**. The constants
  are filled in from the first computed run, so no number in them is typed from this plan. That is the proof the
  constants are real.
- When t16/t17 migrate a section, the "live equals constant" assertion for **that section only** is retired with a
  comment naming the task, and the density gates keep dividing by the constant. No gate ever divides by a value that
  a later task deleted.
- The counts come from data **[estimate from grep: 64 lines, 106 fighters + 2 interceptors; deep_space 18 lines,
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
- **Density (C4) gates**, in `test_level1_fighter_spawns.gd`. The numerator is computed from the shipped configs and
  `tests/helpers/level1_drone_concurrency.gd` (generalised to take a lifetime function per kind). The denominator is the
  §2.9.1 **constant**:
  - the **attack-capable peak** (first three per fighter squad, first two per Gatling squad) ≤ **1.5×**
    `_LEGACY_PEAK_FIGHTERS`;
  - the **all-alive peak** ≤ **2.0×** `_LEGACY_PEAK_FIGHTERS`;
  - the **peak shots/s** ≤ **1.25×** `_LEGACY_PEAK_SHOTS_PER_S`. AI fighters count max burst / (burst gap × size +
    the minimum burst period ≈ 1.2 s); a Gatling counts 12 / 2.8.
  - **[judgement]** The ratios are tighter than the drones' 2.0/2.5, because shooters make more noise per body than
    rammers.
- **Pre-approved levers**, in order, to use only if a gate fails:
  1. Fighter `engage_seconds` 6.0 → 4.5;
  2. `passes` 2 → 1 in Assault (a new config field, `assault_passes`);
  3. split a formation of 5+ into two squads.

  Any other change needs the owner.

#### 2.9.3 cloud_descent (t17): the ENEMIES_CLEARED section (arithmetic corrected for review B4)

- The same edit for its 27 fighter lines. The last fighter wave triggers at 72.0 s. Its latest fighter entries are the
  two `.delay(0.8)` lines at **72.8 s**; the V3 at delay 0.5 lands at 72.5 / 72.6. The last wave overall is the drone
  wave at **76.0 s**.
- **When the clock starts.** `WaveManager._process` emits `waves_complete` **on the tick the last wave triggers**, at
  76.0 s. Delayed spawns are `create_timer` awaits that run after that. So the ENEMIES_CLEARED clock ends at 76.0 + 10 =
  **86.0 s**, not 86.8 as Revision 1 said. The existing drone formula already counts from the trigger
  (`last_wave_max_delay`).
- **Deadline (X8)**, in `test_engagement_deadline.gd`, per fighter entry, in the existing file's strict form:

  `(entry_time − last_wave_trigger) + engage_seconds + deferral + worst_exit + MARGIN < enemies_cleared_timeout`

  - `entry_time` = wave trigger + entry delay + formation slot delay.
  - `deferral` = `burst_telegraph + max(aimed_max × aimed_gap, forward_max × forward_gap)` (§2.4.1), 0.8 s. This is
    the term Revision 1 left out.
  - `worst_exit` = the Razor-shaped formula, because a fighter can start DISENGAGE at `max_speed` heading away from
    its exit edge: `(max_speed + exit_speed) / min(acceleration, braking) + (exit_distance + max_speed² / (2 ×
    braking)) / exit_speed`, where `exit_distance` is the live half-short-side of `projectile_world_rect()` (the
    existing `_exit_distance()`).
  - **[estimate]** (820 / 700 = 1.17) + ((804 + 64) / 520 = 1.67) ≈ **2.84 s**.
  - **[estimate]** worst entry, 72.8 s: (72.8 − 76.0) + 6.0 + 0.8 + 2.84 + 0.5 = **6.94 < 10**. In absolute terms,
    82.94 vs 86.0: a margin of ≈ 3.1 s.
  - There is **no bullet term** (see the correction at the top).
- **Boundary rows**, each naming its delay so it proves something:
  - **A fighter entry moved into the 76.0 s wave at delay 0.8** (that wave's own latest delay):
    0.8 + 6.0 + 0.8 + 2.84 + 0.5 = **10.94 ≥ 10: fails.** The test asserts that the computed value exceeds the
    timeout, not just that the function returns false. (At delay 0 it would be 10.14, also failing, but too thin a
    margin to serve as a boundary that survives tuning.)
  - **A Gatling at delay 0 in the last wave of any ENEMIES_CLEARED section:** 0 + 7.0 + 2.08 (its deferral, §2.6) +
    ((260 + 520) / 600 = 1.30) + ((804 + 37.6) / 520 = 1.62) + 0.5 = **12.5 ≥ 10: fails**. This is the Razor
    precedent. A separate plain assertion keeps the Gatling scene out of every ENEMIES_CLEARED section's waves.
- **Real run:** `tests/integration/test_level1_fighter_exit.gd`, the Ph2 `test_level1_drone_exit.gd` shape. It uses a
  real `WaveManager` loaded with cloud_descent's waves from 66 s onward, and a stationary, hurtbox-less player stub. It
  asserts that the container empties within `enemies_cleared_timeout` of `waves_complete`, that every fighter leaves in
  DISENGAGE, and that none has an `EnemyPathMover`. It prints the measured margin.

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

1. **`t1-pin`** (test): the §2.9.1 level-1 fighter/interceptor pin; the legacy peaks and shots/s **frozen as
   constants** and asserted equal to the live computation; and the station rail-fire test. It runs first, because
   every later task edits what it pins.
2. **`t2-rounds`**: the §2.2 four round scenes, `EnemyRounds`, `EnemyBullet.reset()` restoring the authored speed and
   damage, and the per-round lifetime sweep using **today's** speed sources (regex + `InterceptorConfig`), plus the
   Heavy Shell fixture-shooter test.
3. **`t3-burst-patterns`**: the §2.3 `BurstClock`; the pattern `rng` / `spread_angle` / `aim_point` fields; the shared
   `EnemyMover.sprite_forward_angle_of()`; nose-correct forward fire and `EnemyPathMover` facing, with a
   two-convention test using angular tolerances.
4. **`t4-convergence-field`**: X6, the `SquadController.convergence_point` and `convergence_stage` fields, cleared on a
   LEAD change, with `leave()` erasing a member's stage. Unit tests.
5. **`t5-w-formation`**: the §2.5 `WFormation` class plus `w_formation()`, with a layout test.
6. **`t6-rename-fighter`**: §2.1 `git mv`, the class renames, every roster (including `test_base_enemy.gd`'s flip
   list), the WaveBuilder path, the lifetime test's regex path, and the `test_enemy_path_mover.gd` fixture (X4). **No
   behaviour change**: the t1 pin and every legacy test stay green.
7. **`t7-rename-gatling`**: the same for the interceptor, including the `gatling_interceptor()` call sites and
   `InterceptorConfig` → `GatlingInterceptorConfig` in the lifetime test.
8. **`t8a-fighter-shell`**: the rebuilt `fighter.tscn` (brain, mover, light, two controllers, both pools as root
   children), the extended `FighterConfig` with the rail fields, the §2.8 Fighter rail fallback, `states/` deleted, and
   a **minimal** `FighterBrain`:
   - the phase enum and `enter_phase` seam;
   - APPROACH as a plain intercept;
   - the Assault budget and DISENGAGE;
   - no firing in AI mode yet.

   On rails it is behaviour-neutral, which is what t1 guards. The lifetime sweep switches from the regex to config
   fields.
9. **`t8b-fighter-run`**: the §2.4.1 pass geometry (APPROACH to `S`, RUN_IN path following, EXTEND, TURN, REPOSITION
   routing), the §2.4.2 weapon selection with hysteresis and the nose-cone rule, the telegraph, the burst deferral, and
   the solo dual-mode specs.
10. **`t9-fighter-squad`**: §2.5 roles → pass kinds, the LEAD window open/close, the flank answer-once and wait, the dry
    REAR, the latched-pass / REPOSITION-only side-change rule, and handoff/regroup tests through a real `WaveManager`.
11. **`t10-gatling-windows`**: the §2.6 solo Gatling, pressure windows, side-on movement with the §2.6 side rule, the
    SWING_IN budget rule, the §2.8 Gatling rail fallback, the lifetime sweep's Gatling config fields, and the dual-mode
    specs.
12. **`t11-gatling-convergence`**: §2.6.1.
13. **`t12-shooter-idle`**: §2.10 minimal idle for both brains.
14. **`t13-hub-patrol`**: §2.10 hub spawn and the clearance sweep.
15. **`t14-art-fighter`**, **`t15-art-gatling`**: the §2.7 sprites, keeping the node type.
16. **`t16-level1-duration`**: §2.9.2.
17. **`t17-level1-cloud`**: §2.9.3.
18. **`t18-docs`**: `updating-project-docs`; both `ENEMY.md` files (the Gatling "fires forward" correction);
    `docs/enemy-roster.md`; `assault.md` / `global.md` / `PROJECT.md`; `docs/BULLET_POOL.md`; the CLAUDE.md gate
    paragraph (the new gates: the round lifetime sweep, the fighter pin/density, the fighter deadline rows, the
    rail-fire test); DECISIONS *as built*; and the dossier.

**Dependencies:**
- Roots: t1, t2, t3, t4, t5.
- t6 needs t1 (the pin must exist before anything moves) and t2 (both edit `test_enemy_bullet_lifetime.gd`; t6
  repoints the regex path that t2's sweep reads). t7 needs t6, because both edit the same rosters, `wave_builder.gd`,
  the station file and the lifetime test.
- t8a needs t2, t3 and t6. t8b needs t8a. t9 needs t8b, t4 and t5 (the regroup test uses a W5).
- t10 needs t2, t3, t4 (the SWING_IN rules read the squad fields), t7 and t8b (the same rosters and
  `test_enemy_dual_mode.gd`; serial order is explicit). t11 needs t10.
- t12 needs t9 and t11 (it appends phases to both brains after their combat is final). t13 needs t12.
- t14 needs t9. t15 needs t11. Each edits its enemy's scene only after the combat work is done.
- t16 needs t1, t9 and t11. t17 needs t16.
- t18 needs everything.

---

## 4. Test plan

Boundary cases are in **bold**. "Dual" means the case runs in both harnesses. Angles are compared with
`angle_difference` and vectors with `assert_almost_eq`, never bit-for-bit (review should-fix 2).

| File (task) | Cases |
|---|---|
| `tests/integration/test_level1_fighter_spawns.gd` (t1; updated in t6/t7/t16/t17) | The pinned spawn list equals the live one, row by row, counted from data. **`_LEGACY_PEAK_FIGHTERS` and `_LEGACY_PEAK_SHOTS_PER_S` equal the values computed from the live rails**, per section, until that section is migrated (§2.9.1). After t16/t17: `movement == null` and `free_after` unset for every fighter and Gatling; triggers, offsets, delays and formations unchanged; no `aim_mode` prop left in level 1. Density ratios ≤ 1.5 / 2.0 / 1.25 **against the frozen constants**. **A fighter line given `.move()` again fails. A 3rd Gatling added to deep_space's pair pushes shots/s over (verified once by hand)** |
| `test_station_reinforcements.gd` (t1; still green after t6–t10) | `test_rail_reinforcements_fire`: every TOP fighter and LEFT/RIGHT squad ship fires ≥ 1 bullet within 2 s. The interceptor half-extent is read from the scene, not a literal 37 (C13). **The rail fighter's shot direction for `aim_mode = "FORWARD"` lies along its travel** (`angle_difference` < 1e-3) |
| `tests/integration/test_enemy_rounds.gd` (t2) | Every `EnemyRounds` scene is an `EnemyBullet` with HitBox 256/128, a `ProjectileLifetime` and the table's speed, damage and shape. `reset()` after a pattern changed its speed/damage restores the scene's values. **The Scatter Round expires at ≤ 450 px of travel; the Pulse is still alive at 1280 px.** Heavy Shell fired by a fixture shooter hits a player-hurtbox stub for 20. `pool_size_for` unit cases, **including a rail cadence (burst of 1)** |
| `test_enemy_bullet_lifetime.gd` (t2 sweep; t6/t7 repoint; t8a/t10 switch to config fields) | The per-round sweep `max_distance / min_fired_speed ≤ max_time`, with the range floor. After t10, every speed comes from a config field, **including the rail speeds (Pulse 250 / 420, Gatling Stream 220)**, and none from a regex. **A synthetic round at 100 px/s with the shared 18 s / 2400 px fails** |
| `tests/unit/test_burst_clock.gd` (t3) | `start(4, 0.1)`: advancing by 0.05-step totals gives shot times 0, 0.1, 0.2, 0.3, then stops. **A single `advance(1.0)` returns exactly 4**, never more. `stop()` mid-burst. **`start(0, …)` fires nothing** |
| `test_attack_patterns_forward.gd` (t3) | The forward shot direction equals the actor's travel direction for `sprite_forward_angle` `PI/2` **and** `-PI/2`. **A ship with no `sprite_forward_angle` property gets the legacy `DOWN.rotated(rotation)`, within 1e-5 per component.** `aim_point` overrides `TargetInfo`. Seeded `rng` jitter is reproducible and within `±spread_angle`. `EnemyPathMover` facing equals the legacy `atan2(-vel.x, vel.y)` for `PI/2` **as an angle** (`angle_difference` < 1e-5) over 8 headings, **including `(−1, −1)`, where the raw values differ by 2π**, and is correct for `-PI/2`. `EnemyMover.sprite_forward_angle_of()` is the only reader: a source sweep finds no other `get(&"sprite_forward_angle")` |
| `test_squad_controller.gd` (t4, extended) | `convergence_point` starts `INF` and `convergence_stage` empty; both persist across non-LEAD joins; **both clear when the LEAD leaves or a closer member takes LEAD**; `leave()` erases only the leaver's stage key |
| `test_wave_builder_formations.gd` (t5) | `WFormation` W5 slot offsets (x = −120, −60, 0, 60, 120; y = 0, −40, 0, −40, 0) and delays (0.2, 0.1, 0, 0.1, 0.2); **`w_formation(1)` is a single slot at the origin with delay 0**; a W5 expanded by `WaveManager` is one squad (the Ph2 fixture) |
| `test_enemy_path_mover.gd` (t6) | The `AIStateMachine` lookup is pinned on the fixture scene |
| `tests/integration/test_fighter.gd` (t8a) | The scene: both `BulletPool`s are direct children of the root; pool sizes ≥ `pool_size_for` for the AI **and** the rail cadences (Pulse ≥ 12, Scatter ≥ 7). Rail: `suspend_ai()` → the controller self-times at 0.8 s (aimed, 250 px/s) or 0.3 s (FORWARD, 420 px/s), from config fields. **`aim_mode = "FORWARD"` on an AI fighter changes nothing.** Assault budget: DISENGAGE at `engage_seconds` and free outside the world rect. Config pins `turn_rate × max_speed ≤ acceleration` |
| `tests/integration/test_fighter.gd` (t8b, extended) | Dual: the phase sequence APPROACH → RUN_IN → EXTEND → TURN → REPOSITION → RUN_IN (second pass). **Open Space pass geometry, from §2.4.1's worked check, with a player holding course: the closest approach of a FLANK_LEFT-shaped pass is `pass_offset` ± 40 px on the lane side (`(X − P)·h > 0`, ahead); FLANK_RIGHT-shaped is `pass_offset + flank_lane_gap` ± 40; FRONTAL is `pass_offset` ± 40 on side `σ`.** The same geometry with the player moving at 200 px/s along `h` (the line re-anchors on `P̂`). The TURN radius is within 15 % of `max_speed / turn_rate`. The fighter's body never overlaps the player hurtbox. A solo fighter alternates FLANK_LEFT- and FLANK_RIGHT-shaped passes. **RUN_IN never stalls: the seek target is always ≥ `lookahead` − 1 px ahead along `u`.** Assault: flank and solo passes are lateral (`|vel.x| > |vel.y|` through RUN_IN); **with the player within 100 px of the corridor top the lane flips behind**; **with the player 150 px from a side wall the bearing flips to the open side (`min_run_length`)**; the fighter stays in the corridor until DISENGAGE. **Weapon selection:** in TURN, nose on the player at 250 px → FORWARD 5–7 Scatter shots along the nose; at 400 px → AIMED 3–5 Pulse shots; **at 330 px after an AIMED burst stays AIMED, and after a FORWARD burst stays FORWARD (hysteresis)**; **a FORWARD opportunity with the player 30° off the nose is skipped, not spent**; the mode does not change mid-burst when the distance crosses the threshold; `weapon_mode_changed` emits only on a change. Cadence: the gap between shots is 0.10 / 0.05 s ± one physics tick; at most one burst per pass leg; CHARGING precedes every burst by 0.3 s. **Budget expiry during a telegraph or burst: DISENGAGE starts when the burst ends, within 0.8 s of expiry** |
| `tests/integration/test_fighter_squad.gd` (t9) | A real `WaveManager` spawns `fighter().formation(v_formation(3))`: roles LEAD + FLANK_L + FLANK_R. Each flank's run comes from its bearing side and passes on its lane (the pincer); the LEAD's pass is FRONTAL. **The window opens on the LEAD's RUN_IN entry and closes on its EXTEND entry; each flank answers it once, and `_answered_window` resets once it reads the window closed.** A flank with no window attacks after `flank_wait_max`. Minimum body separation between members over one cycle ≥ 2 × hull radius. **Killing the LEAD reassigns within the same call**; a W5 with a FLANK killed promotes the closest REAR in the same call. **The side-change rule (§2.5): a role change mid-RUN_IN leaves `b`, `u` and `l` unchanged until the next REPOSITION, and every REPOSITION seek target's segment clears `reposition_min_radius`.** REARs fire 0 shots. Dual |
| `tests/integration/test_gatling_interceptor.gd` (t10) | The scene's `StreamPool` is a root child; pool ≥ 36 (AI) and ≥ 20 (legacy rail), **with the rail starvation named as deliberate**. Dual: the rhythm is CHARGING from SWING_IN; SPIN_UP 0.25 s ± a tick with 0 shots (solo); STREAM fires N ∈ [8, 12] shots at 0.09 s ± a tick; COOLDOWN 0.4 s with 0 shots; REPOSITION; repeat. **Seeds giving N = 8 and N = 12 both occur across a seed sweep, and nothing is ever outside.** Side-on: during STREAM the angle between the Gatling-to-player line and `h` is within 90° ± 35°. **Sides (§2.6): Assault, player at the corridor centre: the first window's SWING_IN target is in the half opposite the player's x, and later windows alternate sides. Player 100 px from the right wall: every window stays on the left (the `min_flank_range` exception). Open Space: windows alternate.** The stream aims at the predicted point (a moving player: the mean round direction leads the current position). **With remaining budget < `swing_in_max` the Gatling never enters SWING_IN; budget expiry during STREAM defers DISENGAGE to COOLDOWN entry, within 2.08 s.** Rail: a constant stream at 0.09 s from config fields |
| `tests/integration/test_gatling_convergence.gd` (t11) | Squad of 2 within join range: **both lights reach CHARGING within one physics tick of each other**; both are on the **same** half-plane; the bearing separation is ≥ 30°; **both STREAM intervals overlap: when both reach SPIN_UP within `sync_wait_max`, their STREAM starts are within one tick and the overlap is ≥ 0.6 s**; every round of both streams is fired with `aim_point` finite, and both aim lines pass within 48 px of the `convergence_point` of that tick; **the window closes on the later COOLDOWN entry, not the LEAD's**. **Bounded wait: with the FLANK placed so that its SWING_IN takes the full 1.5 s, the LEAD streams no later than `spin_up_seconds + sync_wait_max` after reaching SPIN_UP.** A FLANK beyond 570 px skips the window. **The LEAD dies mid-window: the point and stages clear, the FLANK's `aim_point` resets to `INF`, and its stream still fires all N rounds.** The LEAD does not open a new window while one is open. A solo Gatling never sets `aim_point` |
| `test_fighter.gd` / `test_gatling_interceptor.gd` (t12, extended) | Hub idle: no fire while IDLE; the ring spacing follows `member_index`; NOTICING → combat inside `perceive_radius`; RETURNING beyond `lose_radius`; **RETURNING never interrupts a burst/stream**. Assault starts in combat |
| `test_sector_hub_patrol.gd` (t13, extended) | Per-group composition; clearance for all four groups from the generic sweep; the seed is reproducible; a Pulse fired in the hub lands in `EnemyContainer`. **The sweep with a pickup moved inside a shooter's reach fails** |
| `test_engagement_deadline.gd` (t17, extended) | The per-entry fighter rows for cloud_descent (§2.9.3 formula, counted from the 76.0 s trigger, with the 0.8 s deferral term). **A fighter entry in the 76.0 s wave at delay 0.8 computes ≥ 10.9 and fails; a Gatling at delay 0 in any ENEMIES_CLEARED section's last wave computes ≥ 12 and fails; no ENEMIES_CLEARED section contains the Gatling scene** |
| `tests/integration/test_level1_fighter_exit.gd` (t17) | The real `WaveManager` run: the container is empty within the timeout of `waves_complete`; every fighter leaves via DISENGAGE; the measured margin is printed |
| `test_fighter.gd` / `test_gatling_interceptor.gd` (t14 / t15) | On the real scene with the new art: a forward rail shot leaves along the travel direction; the sprite node keeps its type and name, and `test_base_enemy.gd`'s flip cases stay green |
| Invariant gates (t6, t7, t8a, t8b, t10, t14, t15) | Contact damage, contact geometry, hurtbox geometry, config isolation (neutral at 10), single writer (empty allowlist), signal arity, sprite transparency, UID integrity, project load integrity. All stay green, with the rosters renamed |

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| K1 | **Density** (C4). 106 rail fighters with 4–6 s lives become AI fighters that make second passes | The t1 pin plus the t16 ratios, with the levers fixed in advance. The gate cannot judge feel; a human playtest is listed as a known gap |
| K2 | **cloud_descent deadline**: its real-run margin was 1.6 s for drones in Ph2 | The per-entry formula, now counted from the 76.0 s trigger and with the 0.8 s burst deferral (≈ 3.1 s estimated margin), the real-run test, and lever 1 (engage 4.5 s) pre-approved |
| K3 | **Silent rail weapons** (X1) | The fallback ships inside t8a/t10, and the t1 station fire test fails first |
| K4 | **Pool starvation** (C6) is silent (`acquire()` → null plus a warning) | `pool_size_for` pinned per shooter for the AI **and** the rail cadence. The convergence test also counts shots fired against N. The one deliberate exception, the rail Gatling (§2.2), is named in its test |
| K11 | **Pass geometry that only works on paper** (the Revision 1 failure, and the Ph2 Razor t10 lesson) | §2.4.1 carries a worked numeric check that t8b's test recomputes; closest approach is asserted for a moving player too; Assault's clamps have their own boundary cases |
| K12 | **The convergence rendezvous stalls a pair** | The wait is capped by `sync_wait_max`, a leaving member is erased from the stage dictionary, and a LEAD change clears everything. t11 tests each path |
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
| R3.1 Fighter replaces the Light Assault Ship, 56–72 px | t6, t8a, t14 |
| R3.2 Attack run (approach, pass, burst, wide turn, reposition, second pass; acceleration + turn radius) | t8b |
| R3.3 Aimed 3–5 predicted / forward 5–7 fast, chosen by distance | t3, t8b |
| R3.4 Pincer + frontal pass | t9 (three attackers: LEAD frontal + two flanks; see X9) |
| R3.5 Assault: corridor, lateral runs, curved exits; formations only a start | t8a (DISENGAGE), t8b, t9, t16 |
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
| R3.16 Readability + sprites | t8b/t10 (StateLight), t2 (round looks), t14, t15 |
| R3.17 Combat tests in both harnesses | t8a, t8b, t9, t10, t11, t12 |
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

---

## 9. Response to feedback (owner review of Revision 1, CHANGES_REQUESTED)

Every point, and where Revision 2 answers it. The reviewer's confirmations under "Checked and fine" still hold; nothing
here reopens them.

### Blocking

| # | Point | What changed |
|---|---|---|
| B1 | The pass geometry flew the fighter ≈ 67 px from the player | **§2.4.1 rewritten.** A pass is a bearing `b`, a run direction `u = −b` and a lane `l ⟂ u`. The start point `S = P̂ + b·standoff + l` lies **on** the pass line, so the closest approach equals `|l|` by construction. RUN_IN is path following with a look-ahead point, so it never stalls. This is the reviewer's option (a), the Reynolds offset perpendicular to the approach, with the start put on the line. "Side" is now two explicit things per pass kind: the side of approach (`b`) and the side of the pass (`l`) (table in §2.4.1). The worked numeric check gives 160 / 260 / 160 px for FLANK_LEFT / FLANK_RIGHT / FRONTAL, against Revision 1's 67. The t8b test recomputes it, including for a moving player. Assault's clamps (lane flip, `min_run_length`) have their own boundary cases |
| B2 | Gatling convergence was mis-sequenced and its test could not pass | **§2.6.1 resequenced.** The window opens at the LEAD's **SWING_IN** entry, the same tick its light goes CHARGING. A FLANK answers on its next tick, so both lights are CHARGING within one tick. Both then hold in SPIN_UP until both are ready, capped by `sync_wait_max` (0.75 s). The point is **refreshed every tick** for the whole window. The window closes on the **later** COOLDOWN entry, so no participant streams without a point. The shared state is `convergence_stage` (X6: a second data field, still no clock). t11 now asserts **overlapping STREAM intervals**, rounds fired with a finite `aim_point`, the bounded wait and the later-COOLDOWN close |
| B3 | The Assault side rule contradicted the REPOSITION flip | **§2.6 "Which side, in which window".** The opposite-half rule applies to the **first** window only; every later window flips (R3.7 wins). The one exception is when the flipped flank point would sit closer than `min_flank_range` to a player hugging a wall. t10 asserts the first-window rule, the alternation and the wall exception separately |
| B4 | The deadline arithmetic was wrong and missing a term | **§2.9.3 corrected.** `waves_complete` fires on the 76.0 s trigger, so the clock ends at **86.0 s**. The per-entry formula is written in the existing file's relative form and gains `deferral` (fighter 0.8 s = telegraph + longest burst; Gatling 2.08 s = spin-up + sync wait + longest stream). The Razor-shaped `worst_exit` is spelled out. The boundary rows name their delay: a fighter at delay 0.8 in the 76 s wave computes 10.94 and fails; a Gatling at delay 0 computes ≈ 12.5 and fails. Worst real entry: 6.94 < 10 (≈ 3.1 s margin) **[estimate]**, recomputed by the test. §2.4.1 and §2.6 define exactly which phases defer expiry, and the Gatling never starts a window its budget cannot reach |
| B5 | t2 could not read configs that did not exist yet, and collided with t6/t7 | **§2.2 three-step sweep.** t2 keeps today's sources (regex + `InterceptorConfig`). t6/t7 only repoint them and now depend on t2. **t8a** and **t10** move the sweep onto config fields, **including the rail speeds**, which become config fields (`rail_aimed_speed`, `rail_forward_speed`, `rail_stream_speed`). The check runs against the slowest fired speed per round, not the scene default. Each task's acceptance criteria say so |
| B6 | The legacy density baselines were computed from data t16 deletes | **§2.9.1.** t1 freezes `_LEGACY_PEAK_FIGHTERS` and `_LEGACY_PEAK_SHOTS_PER_S` as constants (the Ph2 `_EXPECTED_LEGACY_PEAKS` shape), filled from the first computed run and asserted equal to the live computation while the rails exist. t16/t17 retire only that equality, per migrated section, and the density gates keep dividing by the constants |

### Should fix

| # | Point | What changed |
|---|---|---|
| 1 | Pool sizing ignored the rail cadence | §2.2: every pool is sized to max(AI need, rail need) and tested for both. The Fighter's Pulse pool becomes **12** (rail FORWARD). The rail Gatling is a named exception: its pool stays at the AI need of 36, so its legacy starvation shape is kept rather than turning the station's rails into a true 11 shots/s hose. The test states this deliberately, and §2.8 lists it as a visible change |
| 2 | "Bit-identical" was false | X7, §2.3 and §4: equivalence is angular (`angle_difference`) and per component within epsilon, with the `(−1, −1)` 2π case named. One shared static helper, `EnemyMover.sprite_forward_angle_of()`, replaces the planned copies, and a source sweep asserts it is the only reader |
| 3 | Pool placement | §2.2 *Pool placement*, §2.4, §2.6: every pool is a direct child of the root, and a scene test asserts it |
| 4 | The art tasks missed `_rotate_sprite` | §2.3 defines `sprite_forward_angle` after the flip. §2.7 keeps each enemy's sprite node type and name, and lists what a task must update if it ever changes one (track paths, `test_base_enemy.gd`'s flip list, the angle). t14/t15 acceptance criteria and §4 cover it |
| 5 | The fighter window had no close rule | §2.5: the LEAD closes it on its EXTEND entry, and `_reassign()` closes it on a lead change. Flanks answer once, and the flag resets when they read the window closed. t9 asserts it |
| 6 | Role side vs "no cross-over" | §2.5 *Side changes*: the pass is latched at RUN_IN; a new pass kind is taken only through REPOSITION, whose seek target never passes within `reposition_min_radius`. t9 asserts that rule, not an absolute side |
| 7 | §1 overstated the pincer | §1 reworded. X9 records the deviation from IDEAS §5.3 (three attackers: LEAD frontal + two flanks; a fourth is a REAR), and DECISIONS records it too |
| 8 | t5 needs a W layout class | §2.5: `WFormation` in `global/resources/formation/w_formation.gd`, with `stagger_delay` restored (centre first, outwards) |
| 9 | t8 was too big | Split into **t8a** (scene, config, rail fallback, minimal brain with the budget and DISENGAGE; behaviour-neutral on rails) and **t8b** (attack-run flight and weapon selection). t8a is `medium`: the plan fixes every piece, and the t1 pin plus the station rail-fire test guard it. t8b stays `large`, because it carries the B1 geometry |
| 10 | t7 was `small` | t7 is now `medium` |
