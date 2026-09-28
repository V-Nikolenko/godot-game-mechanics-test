# Research — Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family

Epic `cmufs7ekv000lnm2x7nbswijy`, research task `cmufs7el2000pnm2x80pf0jig`, 2026-09-28.
- The code facts behind everything here are in `1-context.md`, next to this file. Its requirement ids `R3.x` and risk
  ids `C1`–`C13` are reused below.
- Values marked **[judgement]** have no citable source. They are starting defaults, not findings.
- The web research was done by a subagent and merged here. Every number attributed to a URL was read on that page.

---

## 0. Scope check (re-validated against the code, `DECISIONS.md` and the Phase 1–2 as-built sections)

The scope text was written before Phase 2 ran. The code and the as-built notes change or sharpen it in the places
below. The plan and `DECISIONS.md` should record each one.

| # | What changed | Scope text / earlier decision | Now | Consequence for the plan |
|---|---|---|---|---|
| S1 | **The Gatling ambiguity is already settled in code, in the opposite direction from the docs** | IDEAS §5.4 and the scope: "settles whether it fires forward or at the player" | `GatlingAttackPattern.aim_at_player` defaults to `true`, so the shipped Interceptor aims at the player at 11 shots/s. Only `interceptor/ENEMY.md` and `docs/enemy-roster.md` ("always fires forward") say otherwise | This is a decision plus a docs fix, not a behaviour discovery. Recommended: the Gatling **aims its streams at a predicted point** (findings 2 and 4); its *movement* keeps it side-on. `enemy-roster.md` and `ENEMY.md` get corrected |
| S2 | **`lead_target` needs no new primitive** | Ph1: "`lead_target` → Ph3 (it is `TargetInfo.aim_direction`)". Ph2 as-built: "Phase 3 is the first to need `lead_target` / `break_contact`" | `TargetInfo.aim_direction(from, speed, accuracy)` and `intercept()` already are lead targeting. The fighter's post-pass extension is a `turn_toward` curve, not a sniper-style break-contact | Build **neither** as a new `Steering` function unless the plan finds a real caller. `break_contact` stays with the Sniper (Ph4). Say so explicitly, since Ph2 as-built flagged both for Ph3 |
| S3 | **Forward fire is broken for nose-up art (C1)** | Ph1 facing rule: `rotation = heading.angle() − sprite_forward_angle` | `AimedAttackPattern` and `GatlingAttackPattern` fire "forward" as `Vector2.DOWN.rotated(ship.rotation)`, which is only right when `sprite_forward_angle = PI/2`. `EnemyPathMover` also ignores `sprite_forward_angle` (`atan2(-vel.x, vel.y)`) | The forward burst (R3.3) needs a heading-correct forward: `Vector2.RIGHT.rotated(ship.rotation + sprite_forward_angle)`, read duck-typed, with default `PI/2` so legacy users are unchanged. A one-line fix plus a two-convention test. The path-mover facing is a second one-line fix, **or** the new sprites are authored nose-down. Recommend both the pattern fix and nose-down art. The path-mover fix is optional (see S6) |
| S4 | **Rails and brain-driven fire collide for the first time (C2)** | Ph1 t10 note: "Phase 15's migration must decide who ticks fire on a rail" | The station reinforcements keep 2 rail fighters (`shoot_forward`) and 4 rail interceptors. Repointing `WaveBuilder.FIGHTER`/`INTERCEPTOR` (the Ph2 Kamikaze precedent) puts brain-driven shooters on rails, and those **go silent** | Phase 3 has to decide the rule Ph1 assigned to Ph15, at least for these two enemies. Recommended: `on_suspended()` sets `attack.driven_by_brain = false` and installs a rail pattern equivalent to today's weapon, so the controller self-times from `_process`. `aim_mode` stays meaningful **only** on rails. Log it in `DECISIONS.md` as a Ph15 precedent |
| S5 | **Scatter Round and Heavy Shell have no in-scope consumer** | Scope: build the family so "later enemies can pick a round" | Pulse → the Fighter. Gatling Stream → the Gatling. No enemy in this phase is a natural Scatter or Heavy Shell user. The Gunship (Heavy Shell) is Ph10, and the Bomber, Sniper and Ram are Ph4 | Two options. (a) Ship all four rounds as tested scenes with no gameplay user yet. That is honest but ships dead content. (b) Give the Fighter's close-range forward burst a **narrow Scatter** (5–7 pellets in a ≤ 15° cone, short `max_distance`), which reads as "short-range spread" and differs visibly from the aimed Pulse burst, and ship Heavy Shell tested but unused. **Recommend (b)**, with Heavy Shell's first consumer recorded as Ph4/Ph10. The plan must not invent a Heavy Shell user outside scope |
| S6 | **The `"AIStateMachine"` lookup loses its last user** | Ph1: retire it in Ph15, "needs the light assault ship on a brain first" | If `light_assault_ship/` is replaced, the lookup's only real subject goes with it. `test_enemy_path_mover.gd` pins it **on `light_assault_ship.tscn`** | Either repoint that test at a fixture scene with an `AIStateMachine` child (keeping the lookup until Ph15, as decided), or retire the lookup now. Recommend **keep plus a fixture**, which honours Ph1's decision with minimal churn |
| S7 | **There is no W formation** | Scope and IDEAS §17: "V, W, wedge, line, diagonal, cluster" | `WaveBuilder` has `v_`, `wedge_`, `line_`, `diagonal_` and `cluster_formation`. No level uses a W | Add a small `w_formation(count, spread, row_gap, stagger)` layout: a zig-zag, two V's side by side. It is cheap, and it closes the scope wording. No level needs to use it |
| S8 | **Formation → role handoff mostly exists already** | Scope: "formations become spawn layouts that hand off to squad roles" | Ph2 t5: a `formation()` is automatically one squad, `WaveManager` sets `entity.squad` before `add_child`, and `SquadController._reassign()` fully recomputes roles by distance on every join and leave. The first member closest to the target becomes LEAD | The *handoff* is already done for any AI enemy with a `squad` property. What Phase 3 adds is (1) **fighter semantics for the roles** (LEAD = frontal pass, FLANK_L/R = pincer, REAR = dry pass or reposition), (2) the W layout, and (3) tests proving handoff and regroup **for fighters** (V spawn → roles → kill the LEAD → recompute). No new board API is expected, except possibly the convergence pairing (C8) |
| S9 | **The hub ambient spawn needs an idle behaviour, and idle for other families is Ph14** | DECISIONS Ph2: "Idle profiles for other families stay in Ph14 and must use `AnchorIdle`" | R3.20 puts both enemies in `SectorHub` now. Without idle they would engage from frame 0 wherever they spawn | Pull forward the **minimum**: an `AnchorIdle` ring or drift for each (Swarm idle-ring shape), with no bespoke idle legs. Richer idle stays in Ph14. Extend `test_sector_hub_patrol.gd`'s clearance sweep with the new groups' bearings, and fix its child-count assertion. Record it as a scope change |
| S10 | **ENEMIES_CLEARED waits on bullets too (C3)** | Ph2 deadline formula: spawn delay + budget + exit only | `LevelDirector._wait_enemies_cleared` polls `enemy_container`, and in-flight enemy bullets live there. Drones fired nothing and Razors are DURATION-only, so Ph2 never met this | Fighters in `cloud_descent` (10 s timeout) introduce the first shooter in an ENEMIES_CLEARED section under AI lifetimes. The deadline test needs a **last-shot bullet flight term**. Heavy Shell is barred from ENEMIES_CLEARED sections (a boundary case, like the Razor's) |
| S11 | **The level-1 migration is ~20× the Phase 2 drone migration in shooters** | Scope: "Level-1 … spawns move to the new enemies … timing preserved" | 106 fighters in 62 lines, all on `.move()` (55 `straight`, 4 `arc`, 3 `u_sweep`), plus 2 interceptors on `player_focus`. Loose side runs cross at `straight(265)` design = 530 px/s and are freed after 4–6 s | A characterization pin first (the Ph2 t1 pattern), then the migration, then density and deadline gates. It is at least two tasks, and probably split by section (see §4.7) |
| S12 | **Sprites** | Scope: new strict top-down 56–72 px | Today the fighter's `assault.png` is 64×64 and the interceptor's `interceptor.png` is **64×74** (out of range) | Two PixelLab sprites, 64×64 (fighter) and 64×64 or 72×72 (Gatling). Apply the S3 nose-direction choice at generation time |

Nothing in scope turned out to be already done, apart from the squad handoff mechanics (S8) and the Gatling's aim
(S1). There is no burst, salvo, spin-up or bullet-variant code anywhere (`1-context.md`).

---

## 1. Findings from shipped games and practitioner sources

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| 1 | **Cap simultaneous attackers, and scale the cap with difficulty.** FreeSpace 2's `ai_profiles.tbl` has `$Max Player Attackers`, "the maximum number of ships allowed to be attacking the player at any given time". The same table scales turn time, the in-range wait before firing, and the fire delay per difficulty. It also has native **burst fire**, whose length depends on "ammo remaining, distance to target, angle to target, and this multiplier". | The owner's 3-fighter pincer plus a frontal pass means **4 attackers at once**, which is FS2's *Medium* value. Everything firing at once reads as noise. Slowing hostile turns is FS2's easy-mode lever, and it maps directly onto our turn-radius design. | Max Player Attackers `2, 3, 4, 5, 99` (Very Easy…Insane). AI Turn Time Scale `3, 2.2, 1.6, 1.3, 1`. AI In Range Time `2, 1.4, 0.75, 0, −1` s. Hostile fire-delay scale `4, 2.5, 1.75, 1.25, 1`. Circle-strafing is only attempted when side-thrust ≥ ⅔ of the target's speed. **[judgement]** Only LEAD + 2 FLANKs fire; REARs fly **dry** repositioning passes. That is 3 shooters, under FS2's Medium, and it needs no new board API. | https://wiki.hard-light.net/index.php/Ai_profiles.tbl (403 to WebFetch; read via `scripts/fetch-page.sh`) |
| 2 | **Attack tokens (DOOM 2016).** "each type of attack … has a limited number of tokens". A demon requests one and releases it afterwards. Demons can "steal tokens from each other if they feel they're better suited", and token counts vary by difficulty. Enemies without a token keep up pressure without attacking. | Tokens make a squad legible, but idle token-waiters look passive unless they have something to do. That is the REAR's dry pass. `SquadController`'s full recompute is already a form of stealing, because the closest member takes LEAD. Adding separate token *categories* (frontal / flank / convergence pair) is more arbitration code than this phase needs. | The article gives no counts. | https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- |
| 3 | **A fly-by or strafing run is *offset pursuit*.** Reynolds: "a path which passes near, but not directly into a moving target … spacecraft performing fly-bys or aircraft conducting strafing runs". Aim at a point offset by radius R from the predicted position, with prediction T = D·c. Leader-following arrives at "a point offset slightly behind the leader". | The fighter's pass is offset pursuit with R = the pass-beside distance. Opposite signs of R on two flankers **produce the pincer geometry for free**, with no choreography. Pure steering cannot guarantee a *wide* turn, so the turn needs its own phase with a turn-rate bound, which is the Ph2 `turn_toward` rule. | Formulas only. **[judgement]** R ≈ 150–180 px, about 2.5 hull radii of a 64 px fighter plus the player's ~30 px hurtbox. T = `clamped_lead_time(d, speed, 0.3, 0.8)`. | https://www.red3d.com/cwr/steer/gdc99/ |
| 4 | **Imperfect aim is a design tool.** First-order lead is enough, especially "when you want to sometimes miss". Designs use "a pseudo-random perturbation of the aim vector or diceroll-based 'dramatic misses' to give a sense of skilled vs. unskilled NPCs". Intercepts can have **no solution**. | Aimed bursts should lead (accuracy < 1 plus small seeded jitter), while the forward burst does no aiming at all and the pass geometry does it. Convergence should be both Gatlings aiming at **one shared predicted point with independent small error**: overlap without a guaranteed hit. This is our synthesis, not a documented pattern. | No numbers. **[judgement]** Aimed burst `accuracy` 0.7, per-shot jitter ±2°. Convergence shared point T = clamp 0.4–0.8 s, per-stream error ±3°, from the brain's `rng`. | https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting |
| 5 | **Aimed-only fire gets "streamed", so mix aimed and fixed-trajectory fire, and leave lanes.** Boghog: aimed patterns are "good for pressure, allows conscious manipulation by the player"; static patterns are "good for creating obstacles". "The aimed bullets force the player to move, while the static pattern makes their movement more difficult." Avoid patterns that "entirely block off huge chunks of the screen". | A stream aimed at the *current* position trails behind a moving player, which is weak. The predicted point makes it a positional threat, but two converging streams on the predicted point can close every lane. **Leave one side open:** put both Gatlings on the **same half-plane** of the player (e.g. 40–60° apart on its left), so escaping away from them works. Pulse and Gatling are the "aimed" layer; Scatter and Heavy Shell are the "static" layer. | Only ratio read: focus speed ≈ ⅔ normal (player movement, not bullets). | https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101 |
| 6 | **Bullet readability rules.** Glowing light cores next to dark borders. Prefer reds, pinks and purples, since yellow and orange "overlap with explosions & golden items". Chunk bullets, because "single stray bullets are hard to read and can often feel unfair". Elongate fast bullets or give them trails, and match sprite length to speed. Draw "smaller, faster bullets … over bigger, slower bullets". Use small central hitboxes for enemy bullets. Round bullets "do not telegraph their movement direction". | Maps onto the family. **Pulse**: an elongated red-pink bolt. **Gatling Stream**: a thin short streak, drawn on top. **Scatter**: small pellets, always fired as a fan, never as strays. **Heavy Shell**: a large round with a bright core and dark rim, drawn below, with a hitbox smaller than the visual. Today's `EnemyBullet` is **orange** `Line2D`, which the rule says to avoid. Recolouring every enemy bullet changes the look of every shooter, including the station, so keep the legacy look on the Pulse-equivalent default or recolour deliberately; the plan must pick one. | SLYNYRD non-foreground layer adjustment S −20, C −15, B +15 (Aseprite). | https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101 · https://www.slynyrd.com/blog/2026/7/26/pixelblog-63-horizontal-shmup · https://sparen.github.io/ph3tutorials/ddsga2.html |
| 7 | **Squad coordination = simple slots plus emergent geometry, made visible (F.E.A.R.).** Squads are re-clustered by proximity. Squad behaviours "find A.I. that can fill required slots" (e.g. a suppressor plus movers), and individual needs can trump orders. Orkin: they "did not have any complex squad behaviors at all". Flanks emerged from each AI choosing cover on either side. And: "There is no point … implementing squad behaviors if … the coordination of the A.I. is not apparent to the player." | This supports "formations are spawn layouts, then roles". The pincer should *emerge* from each flanker's own offset-pursuit side (finding 3), not from a scripted manoeuvre. The convergence pair is F.E.A.R.'s suppressor slot, and it must be **visibly** paired, e.g. both StateLights go CHARGING together, or players never notice it. | Four squad behaviours only (Get-to-Cover, Advance-Cover, Orderly-Advance, Search). | https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf (via reader proxy) |
| 8 | **Slot reassignment and pooling variants.** (a) Game AI Pro 2 ch. 20: greedy nearest-slot assignment "doesn't always work" because members cross paths. Optimal assignment is O(n!); the cheap fix is to sort members and slots spatially the same way and assign i→i. (b) Godot forum: with differently shaped bullets, one scene per type in a keyed pool was recommended over reshaping one scene at runtime, and a hidden node still collides unless its shape is disabled. | (a) `SquadController._reassign()` already re-sorts on every change instead of shifting ranks up, which is the recommended fix. Phase 3 adds nothing here, but a fighter regroup test should assert no two members swap sides across the player. (b) **One scene per round, one `BulletPool` per round per shooter**, matching the existing `bullet_scene` + `acquire()` contract. A variant-data single scene would have to swap shapes on every `acquire()`, and `reset()` already fails to restore HitBox damage. | Forum example ~500 bullets × 8 types (search summary, not re-verified). | http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter20_Hierarchical_Architecture_for_Group_Navigation_Behaviors.pdf · https://forum.godotengine.org/t/object-pooling-with-bullets-of-different-hitboxes/81553 |

Also relevant, with no numbers. Stout: a projectile telegraph is typically charge particles at the barrel, a rising
sound, then a flash, and "it becomes fair" because the player saw it coming. This backs the Gatling spin-up as *the*
telegraph (https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing).

**What the research changes in the design:**
- Finding 1 plus the existing roles give an **attacker cap with no new API**: LEAD and FLANKs fire, and REARs fly dry.
- Finding 3 makes the pincer emergent: per-role signed offset pursuit.
- Findings 4 and 5 shape convergence: one shared predicted point, independent seeded error, both shooters on the same
  half-plane so a lane stays open.
- Finding 6 drives the round visuals and flags today's orange bullet.
- Finding 8 settles one-scene-per-round.
- The 0.25 s spin-up is short against FS2's 0.75 s Medium "in range" wait. Keep the owner's 0.25 s *mechanical*
  spin-up, but start the CHARGING light when the Gatling **commits to its swing-in**, so the visible telegraph is
  ≈ 0.5–0.75 s. **[judgement]**

---

## 2. Candidate approaches and tradeoffs

### 2.1 How a burst or pressure window is produced

| Option | For | Against |
|---|---|---|
| **A. Brain-sequenced fire.** The brain owns the burst clock and calls `attack.fire_now()` N times at `shot_gap`. For the Gatling stream, it flips `attack.enabled` on for the window and lets `tick()` run the cadence. | Uses the existing `AttackController` API unchanged. Burst size, latching and mode choice all live in one place (the brain), deterministic with accumulated `delta` and seeded `rng`. It is the Razor precedent (`fire_now()` from a phase entry). | Burst timing lives in brains, so a later enemy re-implements "N shots at gap g". Mitigation: a tiny `RefCounted` `BurstClock` helper in `global/enemy_ai/` (no clock on the board, and no node). |
| **B. Pattern-level burst.** `AttackPatternResource` gains `burst_count` / `burst_gap`, and `AttackController` sequences it. | Reusable by any `_process`-driven enemy, including the rail fallback. | It changes a shared component that every shooter uses (station gunnery, the razor pulse, gunship), and needs state *in the controller* (patterns are stateless data by design). "Pressure window" = spin-up + stream + cooldown is more than a burst, so this only half-solves it. |

**Recommendation: A**, plus the helper. B's only real advantage is the rail fallback (S4), and that needs only the
existing single-shot patterns at a legacy cadence.

### 2.2 Bullet family structure

| Option | For | Against |
|---|---|---|
| **A. One scene per round** (`pulse_round.tscn`, `scatter_round.tscn`, `gatling_stream_round.tscn`, `heavy_shell.tscn`), each an `EnemyBullet` root with its own visual, HitBox shape, `ProjectileLifetime` values and default damage. Pattern and config supply speed, damage and direction. | Matches `BulletPool.bullet_scene` exactly. It lets each round own its lifetime (Scatter's short `max_distance`), hitbox and z-order (finding 6). Each round is a self-contained scene the lifetime test can sweep. | Four scenes to keep in sync on the HitBox layers. Mitigation: they are *inherited* scenes of `enemy_bullet.tscn`, so only the overrides differ. A test sweeps every round for layer 256 / mask 128. |
| **B. One scene plus a `RoundResource`** applied on `acquire()` | One pool per shooter | Must swap shape, visual and lifetime every acquire, and `reset()` already fails to restore damage. Violates finding 8b. |

**Recommendation: A**, with the rounds under `assault/scenes/projectiles/enemy_bullet/rounds/`, and a sweep test that
derives each round's `max_time`/`max_distance` from **its own** speed band, generalising
`test_enemy_bullet_lifetime.gd`. A per-round sweep keeps the **150 px/s floor honest**: Heavy Shell at ≥ 150–160 px/s
needs no re-derivation of the shared defaults. Deliberately slower means the plan re-derives, as that test's own
header demands.

### 2.3 Fighter movement

| Option | For | Against |
|---|---|---|
| **A. Phase machine** (like Swarm/Razor): `APPROACH` (intercept with clamped lead) → `RUN_IN` (offset pursuit at ±R, burst on entry into the fire band) → `EXTEND` (hold heading ~0.5–0.8 s past the player) → `TURN` (`turn_toward` at `turn_rate`, a visible arc) → `REPOSITION` (to a new start point on the opposite side, or the same side for a flank) → `RUN_IN` again → after `passes`, `REJOIN`/`DISENGAGE`, plus IDLE/NOTICING/RETURNING in Open Space | Proven shape, testable phase by phase with `enter_phase()`, and fits the single-writer gate | The biggest brain in the project. Keep constants in config |
| B. Continuous steering blend (no phases) | Less code | A "wide turn then second pass" is inherently sequential. A blend cannot guarantee the turn happens, and it is untestable against "pass geometry" |

**Recommendation: A.** The key geometric invariants to test are: closest approach during `RUN_IN` ∈
[R − tolerance, R + tolerance] on the claimed side; the `TURN` radius ≈ `speed / turn_rate`; no contact during a pass.

### 2.4 Gatling Interceptor movement and fire

A **phase machine**: `APPROACH` → `SWING_IN` (`strafe`/offset pursuit to side-on at `preferred_range`, perpendicular
to the player's velocity, or to its facing when the player is slow; CHARGING light on) → `SPIN_UP` (0.25 s, with
braking to fire speed) → `STREAM` (`attack.enabled = true`, N = `rng` 8–12 rounds at `stream_interval`, aim at the
predicted point) → `COOLDOWN` (0.4 s, light OFF) → `REPOSITION` (brake, `turn_toward` swing to the other flank) → repeat.

- **In Assault, "flank" is the arena side:** the reference is the half of `inner_rect()` opposite the player's x, per
  IDEAS §5.4.
- **Convergence:** a Gatling squad of 2. The LEAD opens `attack_window_open` on entering `SPIN_UP`, and the FLANK answers
  it once (the Swarm's `_answered_window` precedent). Both compute the **same** predicted point from the shared
  `SquadController.target_position_hint`/heading, plus independent `rng` error. The FLANK claims a side on the **same**
  half-plane as the LEAD, at bearing offset ≥ 30°, per finding 5. Board API needed: none, if "same half-plane" is
  expressed through `claim_side`. The plan must check that the Side enum can express it; otherwise a single
  `convergence_point` field on the board, *written* by the LEAD (no clock).

### 2.5 Weapon selection by distance

- `d < forward_range` at burst time → **forward burst** (Scatter-ish or a fast Pulse, 5–7 shots along the nose).
- `d ≥ forward_range + hysteresis` → **aimed burst** (Pulse, 3–5 shots at the predicted point, `accuracy` 0.7).
- The mode is **latched at burst start** and exposed as a read-only field plus a `weapon_mode_changed(mode: int)`
  signal for tests.
- The boundary test places the player exactly at `forward_range` and at `forward_range + hysteresis − ε`.

Geometry note: the forward burst only hits if the nose points at the player. So it is fired on the **head-on leg** of
a LEAD's frontal pass, or at the end of `TURN` when the nose sweeps across the player, while the flankers passing
beside mostly fire aimed. This makes "chosen by distance" also read as "chosen by geometry", which is the behaviour
the owner describes.

### 2.6 Assault migration of level-1 spawns

The Ph2 t15 recipe, repeated:
1. A characterization pin of every fighter and interceptor entry: trigger, offset, delay, formation, `aim_mode`, and
   `free_after`, computed from `_build_sections()`.
2. Drop `.move()` and `.free_after()` (read only by the path mover), keep `.at()`, `.formation()` and `.delay()`, and
   tag loose lines with `squad(&"w<n>f")`. A distinct suffix from the drones' `&"w<n>"` keeps squads per family (C9).
3. `shoot_forward()`/`shoot_at_player()` on AI spawns become ignored (the mode is chosen by distance). Either strip them
   from level 1, or leave them as the rail fallback's input. **Recommend stripping them in level 1** (the pin records
   what was there) and keeping them where rails remain (the station).
4. A concurrency ceiling per section, attack-capable and all-alive, against the legacy fighter peak, with pre-approved
   levers fixed in advance: fighter `engage_seconds`, `passes` 2 → 1, and splitting a formation.
5. A deadline for `cloud_descent` including the bullet term (S10).
6. A real-`WaveManager` exit case for `cloud_descent`'s last fighter wave (the Ph2 `test_level1_drone_exit.gd` shape).

Legacy lifetimes give the budget: side runs are freed after 4.0–6.0 s, and formations cull on screen exit.
**[judgement]** Fighter `engage_seconds` ≈ 6.0 s (one full pass cycle ≈ 3 s × 2 passes). Gatling `engage_seconds` ≈
7.0 s (two pressure windows ≈ 3 s each). Only 2 Gatlings exist, in `deep_space` (DURATION), so the Gatling is not
deadline-critical. The plan should bar it from ENEMIES_CLEARED sections as the Razor is.

### 2.7 Rail fallback (S4)

`on_suspended()`:
1. `attack.driven_by_brain = false`;
2. `attack.enabled = true`;
3. install a rail pattern that reproduces today's weapon: the fighter's `aim_mode` FORWARD → Pulse forward at 0.3 s
   and 420 px/s, otherwise aimed at 0.8 s and 250 px/s; the Gatling → a stream aimed at the player at 0.09 s and
   220 px/s.

For the Gatling this means rails keep the legacy constant stream, which is acceptable for a rail-only station squad
and is a Ph15 decision to revisit. A station test must assert that a rail fighter actually fires (none does today, see
C2).

### 2.8 Hub ambient spawn (S9)

Add a fighter pair (a squad of 2) and a Gatling pair (a convergence pair) on two new fixed bearings on the 1300 px
ring. Each uses `AnchorIdle` with a Swarm-style shared idle ring (`member_index/member_count`), `patrol_anchor` set
before `add_child`, and `start_engaged` as the test seam. The bearings must be derived by the existing clearance sweep:
every `MissionTrigger`/`PickupBase` plus the player spawn, `dist − worst_idle_offset > perceive_radius`. The Ph2
precedent shows a hand-picked bearing will be wrong (t16 found a missed pickup), so **compute** the bearing in the
plan, don't guess it. `perceive_radius` for a shooter should be ≥ its aimed-burst range, or it fires before it
"notices".

---

## 3. Starting values (all **[judgement]** unless marked)

| Enemy / round | Value | Why |
|---|---|---|
| Fighter | HP 60, contact 20, score 25 | Legacy `fighter_config.tres` (code) |
| Fighter | `max_speed` 300, `acceleration` 700, `braking` 700, `turn_rate` 1.8 rad/s → turn radius ≈ 167 px, diameter ≈ 333 px | The Ph2 rule `turn_rate × speed ≤ acceleration` gives 540 ≤ 700. The diameter fits well inside the 1280 px viewport (C5). The Assault player moves at 360–400 px/s (`move_state.gd`) and the Open Space player at 420 (boost 700), so the fighter is catchable but not trivially outrun. The legacy side-run speed was 530 px/s |
| Fighter | pass offset R 160 px; `passes` 2; lead clamp 0.3–0.8 s; `EXTEND` 0.6 s | Finding 3 |
| Fighter weapons | aimed: 4 shots (3–5), gap 0.10 s, Pulse 300 px/s, damage 8, `accuracy` 0.7. Forward: 6 shots (5–7), gap 0.06 s, 420 px/s (the legacy forward speed), damage 6; `forward_range` 300 px, hysteresis 60 px | IDEAS counts, legacy speed and damage |
| Gatling | HP 70, contact 20, score 75 | Legacy (code) |
| Gatling | `max_speed` 260, `acceleration` 600, `braking` 900, `preferred_range` 380 px, flank band ±35° of perpendicular | Side-on range outside the fighter's pass radius, so the two roles read differently |
| Gatling fire | spin-up 0.25 s (visible telegraph from swing-in ≈ 0.5–0.75 s); 8–12 rounds at 0.09 s (legacy interval, so the stream is ≈ 0.7–1.1 s); cooldown 0.4 s; reposition 1.0–1.5 s; Gatling Stream 240 px/s, damage 4, spread ±0.05 rad from `rng` | IDEAS numbers, the legacy interval and damage, finding 1. The average rate drops from 11 to ≈ 3.5 shots/s, which is the owner's "not background noise" |
| Convergence | shared point T = clamp 0.4–0.8 s; per-stream error ±3°; bearing separation ≥ 30° on the same half-plane | Findings 4 and 5 |
| Pools | Gatling: `rounds_max × ceil(round_lifetime / window_period)` ≈ 12 × 3 = 36. Fighter: 7 × 2 = 14 per round scene | C6 |
| Pulse Round | elongated red-pink bolt, capsule hitbox r 2 | Finding 6 |
| Gatling Stream | thin short streak, drawn on top, capsule r 1.5; `max_distance` ≈ 1400 px | Finding 6; keeps the pool small |
| Scatter Round | 5–7 small pellets per burst, ≤ 15° cone, `max_distance` ≈ 450 px, circle r 2 | "Short-range spread" (IDEAS) |
| Heavy Shell | ≥ 160 px/s (stays above the 150 px/s derivation floor), damage 20, visual ≈ 14 px round with a bright core, hitbox r 5, drawn below | Findings 6 and 8; no consumer this phase (S5) |
| Visuals | Code-drawn (`Line2D` / a code-built `GradientTexture2D`, the `StateLight` precedent), not PixelLab | Spends no art allowance. A code-built texture with a transparent edge passes the transparency gate by construction (the StateLight precedent) |
| Sprites | fighter 64×64, Gatling 64×64 or 72×72, **nose-down** (`sprite_forward_angle = PI/2`) | S3: rail spawns face correctly with no path-mover change |

---

## 4. Risks carried into the plan

Summarised from `1-context.md` C1–C13. These are the ones that shaped the options above:
- **C2 / S4** (a silent rail weapon);
- **C3 / S10** (the deadline with a bullet term);
- **C4** (density; add a shots-in-flight ceiling if the plan can compute one cheaply);
- **C6** (pool starvation, silent);
- **C8** (convergence pairing without a clock on the board);
- **C12** (`class_name` collisions: decide the names first).

**Task sizing hint for the plan:**
- **Large (escalated):** the Fighter brain; the Gatling brain; the level-1 migration (probably split: pin → sections).
- **Medium:** the bullet family; the burst helper plus the pattern forward fix; convergence; the hub spawn; the rail
  fallback plus station tests.
- **Art tasks:** the two sprites.
- **Small:** the W helper; the docs task.

---

## Sources

Read and used:
- https://wiki.hard-light.net/index.php/Ai_profiles.tbl (403 to WebFetch; read via `scripts/fetch-page.sh`)
- https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-
- https://www.red3d.com/cwr/steer/gdc99/
- https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting
- https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101
- https://www.slynyrd.com/blog/2026/7/26/pixelblog-63-horizontal-shmup
- https://sparen.github.io/ph3tutorials/ddsga2.html
- https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf (via reader proxy)
- http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter20_Hierarchical_Architecture_for_Group_Navigation_Behaviors.pdf (via reader proxy)
- https://forum.godotengine.org/t/object-pooling-with-bullets-of-different-hitboxes/81553
- https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing

Tried and unreachable, or not useful:
- https://www.gamedev.net/forums/topic/677818-advice-on-spaceship-combat-ai-3d/: 403, and `fetch-page.sh` failed too.
  Not used.
- The Squadron: Mercenaries devlog (itch.io): reachable but had no numbers. Not used.
- Sparen guide A3: reachable, but nothing on readability.
- No primary source was found for Gatling or minigun spin-up timing (Gungeon, Returnal, DOOM), or for dogfight AI in
  Star Wars: Squadrons, Ace Combat or Descent. The 0.25 s spin-up and all burst sizes are the owner's (IDEAS §5.3–5.4),
  not sourced.

**Judgement calls with no source:**
- the 4-attacker → 3-shooter cap;
- the burst gaps;
- all speeds, ranges and pool sizes in §3;
- convergence as "shared point + independent error + same half-plane";
- pools-per-round being lower risk than variant data (a reading of the forum thread and our `BulletPool` contract);
- starting the CHARGING light at swing-in.
