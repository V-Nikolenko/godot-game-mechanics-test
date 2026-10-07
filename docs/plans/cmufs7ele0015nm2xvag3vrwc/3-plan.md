# Enemy rework, phase 4: Bomber, Sniper and Ram Corvette — plan

Epic `cmufs7ele0015nm2xvag3vrwc`, plan task `cmufs7elo001dnm2xj1ft597f`. Revision 1, 2026-10-07.

This plan builds on `1-context.md` (code facts, requirement ids `R4.1`–`R4.47`, risks `C1`–`C16`) and `2-research.md`
(scope check `S1`–`S16`, findings `F1`–`F13`, approaches §2, starting values §3, deadline arithmetic §4). Both are in
this directory, and this plan does not repeat them. It also builds on
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (all three phases' plan and *as built* sections) and on
`docs/epics-done/cmufs7ekv000lnm2x7nbswijy/REPORT.md`. Where this plan changes an earlier decision, §2.0 says so.

- **[judgement]** marks a value with no citable source. These are starting defaults in `.tres` configs, so they can be
  tuned without code changes.
- **[estimate]** marks a value worked out by hand from scene and level data. The task that owns it must recompute it
  from live data in a test. The Phase 2 t16 lesson: a hand-computed number was wrong there.
- Symbols are cited instead of line numbers, because line numbers drift.

**Facts this plan re-checked in the code (beyond the research):**
- `global/ship_modules/emp_blast_module.gd` and `engine_boost_module.gd` each hold `_IMMUNE_CLASSES` containing
  `"RamShip"`, matched by the script's global class name. A rename silently drops that immunity unless both lists change
  in the same task (§2.6.1).
- `homing_missile.gd::_fly_to_target` steers at the locked target's `global_position` with an instant turn and no
  lifetime except the legacy arena box. A homing rocket deflected by an armoured hull **reaches the hull's centre and
  stays there**, flipping direction every frame (§2.6.1, the `homing_point()` fix).
- `level_2_waves.gd` still spawns rail snipers and bombers. `level_2.tscn` is unreferenced (DECISIONS Ph1), so the rail
  fallbacks (§2.8) are its only consumer outside the interim level-1 builds.
- `BulletPool` connects an anonymous lambda per bullet in `_prewarm()` and frees every in-flight bullet in `_exit_tree()`
  (`cancel_active()`). This confirms C3.
- `HurtBox.received_damage(damage: int)` carries no type. `accepted_damage_types` filters only on `area_entered`.
  The player's rockets are `ROCKET` (`damage_type = 1`; homing 100, warhead 50). The player's bullet is `LASER`
  (`bullet.tscn`, 50).

---

## 1. Problem (player-facing)

**Today:**
- **The Bomber** is a dark wing that slides down the screen on a rail, dropping a bomb straight down every 1.2 s.
  - The bomb is a coloured square that falls, waits for the player, then blows up.
  - It cannot be shot. It vanishes below the camera.
  - The bomber never reacts to where the player is going.
- **The Sniper** drifts across the screen on a straight rail while a red line tracks the player, then fires.
  - 24 of 26 level-1 snipers aim while moving. Several leave before their first shot.
  - The only "hover" behaviour depends on a path whose duration must match a constant (`FLY_IN_TIME`).
  - It never picks a position, never retreats on its own, and ignores anything in the way of its shot.
- **The Ram Ship** is a 32 px sprite that dives straight down at 520–700 px/s.
  - Bullets are silently ignored (its hurtbox does not listen for them) until a missile "breaks" it.
  - It is not in the `enemies` group, so homing rockets, EMP, nova, dash and the beam never pick it.
  - In Open Space none of the three exists.

**After this phase:**
- **The Bomber** angles in and flies a bombing line across where the player is *going*, then escapes on an arc. It picks
  one of three kinds of ordnance from what the player is doing:
  - a **mine chain** across a moving player's path;
  - a slow **gravity bomb** for a close, slow player;
  - a **pursuit bomb** for a far or evasive player.

  Every bomb and mine blinks when armed and can be shot. Killing the Bomber does not clear what it already dropped. In
  Assault the same logic lays walls, diagonals and pockets inside the corridor.
- **The Sniper** backs off and slides to a new firing angle every cycle. The angle is chosen relative to the player's
  heading, and never the same as last time.
  - It stops dead, unfolds its barrel and shows a dim tracking line, then a bright locked line.
  - Then it fires a near-instant rail shot that leaves a fading trail, and breaks away again.
  - While it holds still it is vulnerable. If a rock is in the way it does not fire.
  - In Assault it uses the off-camera part of the corridor, and it never pops back to the same spot.
- **The Ram Corvette** is a mid-size ship with three armour plates: front, left and right.
  - Bullets glance off the plates and the hull with a visible flash. Each rocket breaks the plate it hits, and the
    plate disappears.
  - It lines up on where the player will be, glows while its engines charge for about 0.65 s, then rams through that
    point, overshoots and makes a wide turn.
  - With all three plates gone, the hull takes bullets, the ship gets faster and jinks out of the player's aim, and it
    hits slightly harder.
  - In Assault the charge comes diagonally across the corridor.
- **All three** fly in the Open Space hub and in level 1, where they arrive at the same moments and places as before.

---

## 2. Design

### 2.0 Changes to earlier decisions, stated explicitly

| # | Earlier decision | This phase | Why |
|---|---|---|---|
| X1 | `persist_after_owner_death` "documented only … becomes a `BulletPool` policy in **Ph5**" (Ph1). Ph2 and Ph3 handed it to Ph5. | **Built in Ph4**, in exactly the shape Ph1 designed: a `BulletPool` export (§2.2.3). Ph5 builds owner-distance lifetime and rockets **on** it. | The epic names it, and the Bomber's mines need it: a mine that vanishes when its bomber dies is not area denial (S2). |
| X2 | "Multi-state armour is Ph4's" (Ph1, on `DefenseProfile`). | `DefenseProfile` is **not** extended. Armour is **parts plus a hull rule**: the station's turret-over-armoured-core pattern (§2.6.1, research A3). `apply_alternate()` stays, with no shipped user. Its unit test switches to a fixture. Ph17 may delete it. | A mask-based armour silently consumes bullets (research A1), which the hurtbox-geometry gate and CLAUDE.md forbid. |
| X3 | CLAUDE.md: "any future entity that needs to deflect a bullet … must expose its own `is_armored()`-shaped query". | Extended **additively**: a target may expose `deflects_hit(hit_box: HitBox) -> bool`. Player projectiles ask it first and fall back to `is_armored()`. One shared static, `ArmorQuery.deflects()`, replaces the three copies. | "Deflect a bullet, accept a rocket" cannot be said with a hit-blind query (C1). The station implements no `deflects_hit`, so it takes the unchanged fallback path. |
| X4 | Group `ram_ships`: the player's sniper shot stops on it for 0. The old Ram's layer immunity (mask 33). | **Both retired.** The Corvette joins `enemies`. Bullet immunity becomes the armour rule above. | The epic: "not the old layer-based bullet immunity". |
| X5 | Ph3: "Heavy Shell's first consumer: Ph4 (Bomber/Ram) or Ph10". | **Ph10.** No Ph4 enemy fires a shell. | No IDEAS text for these three asks for one; adding it would build ahead of the spec (S11). |
| X6 | `TargetInfo.line_of_sight(_from)` stub (Ph1). | `line_of_sight(from, space, exclude := [])` delegates to a new static `LineOfSight.clear()` (§2.2.2). Its two stub assertions in `test_target_info.gd` are replaced. | A snapshot holds no world (C7). |
| X7 | — | New duck-typed `homing_point(from: Vector2) -> Vector2` on a homing rocket's target, read by `homing_missile.gd` when present. | Without it a homing rocket parks at an armoured hull's centre (facts above). |
| X8 | Ph2: "Armour collision is Ph4's new mode on the same enum." | `ContactProfile.Mode.ARMOR` is **appended** (value 4) so serialized scene ints do not shift (§2.6.3). | As planned. |
| X9 | Ph1 deferred "`bomb.gd` lifetime" to Ph4. | `bomb.gd` / `bomb.tscn` are **deleted**. Enemy ordnance is a new family under `assault/scenes/projectiles/enemy_ordnance/`, separate from the rounds (§2.3). | Its `create_timer`, camera cull and "down only" break three conventions. |
| X10 | Rails: a shooter on a rail installs a fallback weapon from `rail_*` fields (Ph3 X1). | Kept for all three (§2.8). The sniper's rail fallback keeps its **telegraph**. | Rail snipers stay in level 1 until t21/t22, and in `level_2_waves.gd`. |

### 2.1 Names and places

| What | Where | Notes |
|---|---|---|
| Bomber | `assault/scenes/enemies/bomber/` (`Bomber`, `BomberBrain`, `BomberConfig`) | Name kept. `bomb.gd/.tscn` deleted. |
| Sniper | `assault/scenes/enemies/sniper/` (`Sniper`, `SniperBrain`, new `SniperConfig`, `SniperTelegraph`) | `git mv` of `sniper_enemy/`, Ph2/Ph3 rename precedent. `WaveBuilder.sniper()` and `sniper_enemy()` (alias) are kept. |
| Ram Corvette | `assault/scenes/enemies/ram_corvette/` (`RamCorvette`, `RamCorvetteBrain`, `RamCorvetteConfig`) | `git mv` of `ram_ship/`. `WaveBuilder.ram()` is kept. `ram_ship_damaged.png` is deleted with the new art. |
| Enemy ordnance | `assault/scenes/projectiles/enemy_ordnance/` (`EnemyOrdnance` base script; `gravity_bomb.tscn`, `mine.tscn`, `pursuit_bomb.tscn`; `EnemyOrdnanceScenes` constants + `pool_size_for`) | Not `EnemyBullet`s and not `BaseEnemy`s (C6). |
| Rail round + trail | `assault/scenes/projectiles/enemy_bullet/rounds/rail_round.tscn` (inherited `enemy_bullet.tscn`, the Ph3 rounds shape), `rail_trail.gd` (`RailTrail`, code-built `Line2D`) | `enemy_sniper_bullet.tscn` is deleted in t12. |
| Shared AI | `Steering.break_contact` + `EnemyMover.break_contact`; `global/enemy_ai/line_of_sight.gd` (`LineOfSight`) | Pure statics. |
| Shared components | `global/components/armor_query.gd` (`ArmorQuery`), `global/components/armor_plate.gd` (`ArmorPlate`) | `ArmorPlate` is the first reusable "breakable part". Ph10 modular damage should build on it, not on a new one. |

All three use the Ph3 skeleton (`1-context.md` "Existing code to reuse"):
- a `BaseEnemy` root, with the `Brain` child an `EnemyBrain` subclass, an `EnemyMover` (AUTO) and a `StateLight`;
- `_apply_config` copies config to mover and brain after the brain's `_ready()`;
- `patrol_anchor = Vector2.INF`, and `start_engaged` as the test seam;
- an Assault `EngagementBudget` → DISENGAGE (release the constraint, exit at `exit_speed`), and the rail fallback in
  `on_suspended()`.

Pools are **root children**, sized by `pool_size_for`.

### 2.2 Shared primitives (built first; each is default-off or additive, so none changes shipped behaviour alone)

#### 2.2.1 `break_contact` (R4.22, S1)

`Steering.break_contact(pos, threat_pos, threat_vel, side: float, max_speed: float, lateral_weight := 0.6) -> Vector2`:
- Let `away = (pos − threat_pos).normalized()` and `lat = away.orthogonal() * sign(side)`.
- If the threat is **closing** (`threat_vel · away > 0`), double `lateral_weight`. The ship then steps off the player's
  line of advance instead of fleeing straight down it: a straight flight from a faster pursuer is the one direction the
  player always catches.
- Returns `(away + lat * w).normalized() * max_speed`.
- Degenerate distance (`< 1e-3`): use `threat_vel.orthogonal()`, else `Vector2.RIGHT`, times `max_speed`.

`EnemyMover.break_contact(threat_pos, threat_vel, side, speed)` is the one-line request wrapper, like every other
primitive. Unit cases are in §4.

#### 2.2.2 Line of sight (R4.23, S3, S9, C7, F12)

`LineOfSight.clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array[RID]) -> bool`:
- Ray mask: `CollisionLayers.ENVIRONMENT | CollisionLayers.HAZARD_CONTACT`, the beam's own block mask.
  `collide_with_areas = false`, so hurtboxes, triggers and pickups never block.
- **Opt-in blocking.** A hit blocks only if its collider is in group `asteroids` or answers
  `blocks_line_of_sight() == true`. Any other body (a fighter, the player) is added to the exclude list and the ray is
  recast. This is `beam_behavior`'s excluded-and-recast loop, capped at 4 recasts. Past the cap the line counts as
  clear, and a verbose-gated warning prints.
- It must be called from the physics step only (F12). The brain tick is the physics step.

`TargetInfo.line_of_sight(from, space, exclude := [] as Array[RID]) -> bool` returns `has_target and
LineOfSight.clear(space, from, position, exclude)`.

The hub has no physics blockers, so in shipped content the refusal fires only where asteroids exist. Level 1's
asteroid belt has no snipers. Wrecks are Ph6 and later. **The refusal is real code, proven by fixtures in both
harnesses** (S9). The plan does not invent hub obstacles.

#### 2.2.3 `persist_after_owner_death` on `BulletPool` (R4.39, X1, C3, F13)

- `@export var persist_after_owner_death: bool = false`.
- `_prewarm()` **stores** each bullet's recycle `Callable` in `_recycle_calls[bullet]` before connecting it, so it can be
  disconnected later.
- `_exit_tree()` with the flag on calls `_hand_over_active()` **instead of** `cancel_active()`. For each valid in-flight
  bullet:
  - disconnect the stored recycle callable;
  - connect `expired → bullet.queue_free` (one-shot);
  - drop it from `_active`.

  The bullet is now self-owned. It expires on its own `ProjectileLifetime` (or its own detonation), and the
  one-owner rule holds at every instant.
- `_recycle(bullet)` returns early when `bullet` is no longer `_active` and not `_idle`. This covers a deferred recycle
  already queued in the frame the owner died: the callable was queued before the disconnect.
- With the flag off, the pool behaves exactly as today. `cancel_active()` (the station's explicit stop) is unchanged
  whatever the flag says.
- `ProjectileLifetime`'s doc comment is updated: the flag is built, in Ph4, on the pool.

Why the flag sits on the pool rather than per projectile: ownership is decided where the pool is. A Bomber's three
ordnance pools all set it. Its absence on every bullet pool keeps today's "rounds vanish with their shooter" (Ph3,
recorded) unchanged. Ph5 may add a per-round override if it needs one.

#### 2.2.4 The hit-aware armour query (X3, X7, C1, C2, C4)

`ArmorQuery.deflects(area: Area2D, hit_box: HitBox) -> bool` (static):
- Let `target = area.get_parent()`.
- If `target.has_method("deflects_hit")`, return `target.deflects_hit(hit_box)`.
- Else return `target.has_method("is_armored") and target.is_armored()`, today's rule.

`bullet.gd::_hit_is_deflected`, `homing_missile.gd` and `warhead_missile.gd` call it with their own `HitBox`. Each
keeps its private wrapper name, so the diff is one line in each.

`homing_missile.gd::_fly_to_target` steers at `locked_target.homing_point(global_position)` when the method exists,
else at `global_position`.

**The station is untouched**, because it implements neither new method. `test_space_station.gd`,
`test_station_incoming_damage_paths.gd` and `test_player_bullet_lifetime.gd` stay green unedited (the t4 acceptance).

`ArmorPlate` (`global/components/armor_plate.gd`, a `Node2D`) is the breakable part:
- **Children:** `HurtBox` (layer 512, mask `PLAYER_ROCKETS | PLAYER_HITBOX` = 96, `accepted_damage_types = [ROCKET]`),
  `Health`, and a `Sprite2D` named `Sprite`.
- **Signals:**
  - `broken(plate: ArmorPlate)`;
  - `deflected(hit_box: HitBox)`, emitted from its HurtBox's `area_entered` when a non-rocket `HitBox` overlaps a live
    plate (the deflect flash, R4.36, F11).
- `deflects_hit(hit_box)`: returns `is_alive() and hit_box.damage_type != HitBox.DamageType.ROCKET`. A rocket is
  therefore **consumed** by the plate it breaks (a real damaging hit). A bullet keeps flying.
- `is_alive()`.
- `set_glow(amount: float)`: a 0..1 `modulate` toward warm yellow, on the plate's sprite only (§21: never recolour the
  hull).
- **Break:** when Health reaches 0 it disables the HurtBox (`set_deferred` for both `monitoring` and `monitorable`),
  hides the sprite, bursts an `ExplosionEffect` into the owner's parent, emits `broken`, then `queue_free()`s itself.
  This is "physically disappear".

**Rule:** a plate is never a direct child of the root (it sits under a `Plates` node). The hurtbox-geometry gate's "exactly one
direct-child `HurtBox` that covers the body" therefore holds. This is the station's `Turrets` precedent.

### 2.3 Enemy ordnance (R4.3, R4.4, R4.39, C5, C6)

`EnemyOrdnance extends Area2D` (one script; the kind is an `@export enum Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`
and the scenes differ by authored values):

- **Contract:**
  - `signal expired`;
  - `reset()` restores the authored exports (the `EnemyBullet._authored_*` pattern) and re-arms the child
    `ProjectileLifetime`;
  - `launch(dir: Vector2, speed: float, target_point: Vector2)`.

  Damage, radii and timings are set by the dropper after `acquire()`, from `BomberConfig` fields.
- **Children:**
  - `HurtBox` (layer 512, mask 96, accept all) and `Health` (1): any player bullet or rocket **defuses** it;
  - `ProximityArea` (layer 0, mask `PLAYER_HURTBOX` 128, circle `trigger_radius`);
  - `ProjectileLifetime` (`max_time`, `max_distance`, `use_world_rect`);
  - a code-drawn visual: a filled circle plus a blink ring, red when armed (§21). Ph3 rounds were code-drawn too, so
    no PNG is needed.
- **Clock:** an accumulated `delta` in `_physics_process`, never `create_timer` or `Timer`. It moves itself
  (`position +=`) like `EnemyBullet`, so it is outside the single-writer gate (C6).
- **Detonation:** `ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage, 3)`, then
  `expired.emit()`. **Defuse** (shot): an `ExplosionEffect` pop and `expired.emit()`, **no blast**. This makes shooting
  ordnance always safe and always worth it. It is the "clear rule for what a shot does" (F10), and an owner question in
  §8.
- **Not in `enemies`.** Homing rockets, EMP and the beam's target list ignore it. Bullets and the warhead's straight
  rockets hit it through the hurtbox. It does not count for `ScoreTracker` (never registered).

| Kind | Movement | Arming / trigger | End of life |
|---|---|---|---|
| Gravity Bomb | Keeps `launch` direction at `gravity_bomb_speed` (120) | Armed after 0.3 s. Player within `trigger_radius` (80) → **warning** blink for `gravity_bomb_fuse` (1.0 s) → detonate. It also detonates when it reaches `max_travel` (the drop's distance to its aim point + 120). | `ProjectileLifetime` backstop: 12 s / 1800 px |
| Mine | Ejected sideways for 0.3 s with a decaying velocity (the arc), then **stationary** | Armed after `mine_arm_delay` (0.5 s). Player within `trigger_radius` (80) → 0.5 s warning → detonate | `mine_life` (8 s) → **fizzles** (no blast; fades over 0.3 s) |
| Pursuit Bomb | Launched at `pursuit_launch_speed` (90). For `pursuit_steer_window` (1.5 s) it turns toward `TargetInfo.predicted_position(pursuit_lead)` at ≤ `pursuit_turn_rate` (1.2 rad/s, `Steering.turn_toward`). Then it **freezes its heading** and accelerates to `pursuit_final_speed` (380). | Armed at launch. Player within 48 px → detonate immediately (no warning; the steering was the telegraph) | 10 s / 2400 px |

Blast radius and damage: gravity bomb 48 px / 40 (today's bomb damage); mine 48 / 30; pursuit 40 / 30 [judgement, from
research §3]. `EnemyOrdnanceScenes.pool_size_for(kind, cfg)` sizes the pools from the run cadence and the life:
- mines: `max_mines_per_run (5) × ceil(mine_life / min_run_period)`;
- bombs: 4.

The round-lifetime sweep (`test_enemy_bullet_lifetime.gd`) gains ordnance rows:
- moving kinds: `max_distance / slowest config speed ≤ max_time`;
- stationary mines: time-bound only (`mine_life < max_time`).

### 2.4 Bomber (R4.1–R4.8, S8, S14)

**Scene.** `Bomber` root, `CircleShape2D` body. The contact and hurt shapes share it (the geometry gates). Children:
`Brain`, `EnemyMover` (AUTO; `max_speed` 170, `acceleration` 220, `max_turn_rate` 1.6), `StateLight`,
`GravityBombPool`, `MinePool`, `PursuitBombPool` (all `persist_after_owner_death = true`), and a `Sprite2D` (nose-down,
§2.7). HP 150, contact 35, score 80, carried over from today's config.

**Brain states:** `APPROACH → RUN → ESCAPE → REPOSITION → (APPROACH …)`, plus `IDLE/NOTICING/RETURNING` (hub, t19) and
`DISENGAGE` (Assault).

1. **Prediction.**
   - `v̄` is the player's velocity, smoothed by an exponential moving average with τ = `velocity_smoothing` (0.3 s).
   - `P̂ = P + v̄ · lead_factor · min(horizon, d / run_speed)`, with `lead_factor` 0.6 and `horizon` 1.2 s (F9's damped
     lead).
   - Below `min_lead_speed` (40 px/s), `P̂ = P`.
   - This one function, `predicted_drop_point()`, is the thing the placement test measures.
2. **Ordnance choice**, evaluated at the start of each APPROACH:
   - `|v̄| ≥ mine_speed_threshold` (150) → **MINE**;
   - else `d < gravity_range` (420) → **GRAVITY**;
   - else **PURSUIT**.

   With probability `choice_jitter` (0.2, from `brain.rng`) it takes the next type in that order instead, so a player
   cannot farm one response. Tests set the jitter to 0.
3. **Bombing line.**
   - **MINE:** the line is centred on `P̂`, **perpendicular to `v̄`**, `run_length` long (360). This is a wall across
     the path ahead of a moving player (R4.5).
   - **GRAVITY / PURSUIT:** the line passes over `P̂`, along the bomber's current bearing to `P̂` rotated by
     `approach_angle` (35°) toward its current side. That is the angled approach (R4.2).
   - In Assault both endpoints and every drop point are clamped to `inner_rect().grow(−drop_margin)` (64) (R4.6, S8).
     A clamp that shortens the line below `min_run_length` (160) slides the line along its own direction until it fits.
4. **APPROACH.** A `DubinsPath` (turn radius `max_speed / max_turn_rate`) arrives at the line's start **pointing along
   the line**, the Ph3 rule for attack-run enemies, sampled as seek points like the Fighter's RUN_IN. Capped at
   `approach_cap` (6 s); past the cap it re-plans once from its current pose.
5. **RUN.** Straight along the line at `run_speed` (170). StateLight **ARMED** (red: "it is dropping").
   - MINE drops `mines_per_run` (rng 3–5) on a `BurstClock` with gap `run_length / run_speed / (n+1)`. Each is ejected
     at ±`mine_eject_speed` (90) alternating sideways and backward, so the chain lies in an arc behind the bomber.
     Each mine's **rest point** is clamped in Assault.
   - GRAVITY releases one bomb when `P̂` is `gravity_release_lead` ahead along the line. It inherits the bomber's
     heading and flies at `gravity_bomb_speed`.
   - PURSUIT launches one pursuit bomb at the line's midpoint, aimed at `P̂`.
6. **ESCAPE.** `Steering.turn_toward` away from the player at `escape_turn_rate` (1.4 rad/s), accelerating to
   `escape_speed` (200) for `escape_time` (1.6 s). That is the escape arc (R4.2). A curved path is a brain-side request,
   never the mover's turn cap (Ph2 rule). StateLight OFF.
7. **REPOSITION** (Open Space). Hold an orbit at `standoff` (520) for 1.0–1.8 s (rng), then go back to APPROACH with a
   fresh choice.
8. **Assault.** `engage_seconds` 8.0. Budget expiry during RUN defers DISENGAGE to RUN's end. DISENGAGE is the Ph3 exit
   (nearest rect edge + 64 at `exit_speed` 260, the curved bound). At 8 s an Assault bomber flies one run, rarely two.

**R4.8, "where will the battlefield become dangerous next?":** the player sees the angled lead-in and the red light
before anything drops, and the drops land ahead, not under them.

### 2.5 Sniper (R4.10–R4.25, S6, S7, C8–C11, C14, C15)

**Scene.**
- A narrow hull. HP 60, contact 20, score 50 (today's values, now on a **new `SniperConfig`**).
- Children: `Brain`, `EnemyMover` (AUTO; `max_speed` 320, `acceleration` 520, `braking` 700, `max_turn_rate` 4),
  `StateLight`, `RailPool` (rail round, `pool_size_for` → 2), `SniperTelegraph`, and `Sprite2D` (hull) plus `Barrel`
  (`Sprite2D`, §2.7).
- Muzzle: the barrel tip, read from a `Muzzle` `Marker2D`, never a literal.

**Cycle** (states named as in research §2.5; IDEAS §4's `HIDE` is the BREAK_CONTACT/RELOCATE pair):

```
ENTER → BREAK_CONTACT → RELOCATE → SETTLE → [DECOY] → AIM → LOCK → FIRE → BREAK_CONTACT → …
                                    ↘ LOS blocked at SETTLE end / LOCK end → BREAK_CONTACT (no shot)
```

- **ENTER.** Seek the first chosen firing point (below) at `relocate_speed` (260). Its duration is
  `distance / relocate_speed` by construction, so there is no `FLY_IN_TIME` anywhere (R4.20, S6).
- **BREAK_CONTACT.**
  - `mover.break_contact(P, v_player, side, break_speed 320)`.
  - `side` = the side of the player's velocity line the sniper is already on, so it never cuts across the nose.
  - Lasts until `d ≥ preferred_range × 0.9` or `break_cap` (2.0 s). Then it picks the next firing point and goes to
    RELOCATE.
  - **Every shot is followed by this state.** No transition goes from FIRE toward the player (R4.15).
- **Firing-point selection** (`choose_firing_point()`; F7 weighted sum, F8 filters before scoring):
  - **Player frame:** `f` = `v̄.normalized()` if `|v̄| ≥ 60` px/s, else the player's facing.
  - **Candidates:** seed bearings relative to `f`: ±60°, ±90°, ±135°, 180° (the IDEAS list; "far above/below" is ±90°
    at the long end of the range band). Each gets an rng jitter of ±15°. Range = `preferred_range` ±
    `range_jitter` (Open Space 900 ± 100; Assault 680 ± 80). That is 7 candidates, plus 3 random bearings = 10.
  - **Filters**, in order:
    1. Assault: the point lies inside `inner_rect().grow(−fire_margin)` (96). It may be off camera (S7).
    2. Not within ±`forward_cone` (30°) of `f` while `|v̄| ≥ 200`: never park in front of a charging player.
    3. **LOS clear** (`LineOfSight`) from the candidate to `P`. This ray runs only on candidates that pass 1 and 2,
       capped at 6 rays per selection (F8).
  - **Score:** `w_sep · clamp(Δbearing / 180°) − w_travel · (travel / (2 · preferred_range))`. `Δbearing` is the
    angle between the candidate's bearing and the **last firing bearing**, both measured in the player frame;
    `w_sep` 1.0, `w_travel` 0.4.
  - **Hard rule:** if any candidate has `Δbearing ≥ min_bearing_change` (45°), the best of those wins. Only if none
    does (a player hugging a corridor corner) does the best legal candidate win, and a verbose line logs the fallback
    (C15).
  - Nothing legal at all → hold BREAK_CONTACT for another `break_cap`, then retry.
- **RELOCATE.** `mover.arrive(point, relocate_speed)`. Ends within 12 px, or at `relocate_cap` (4 s), which re-picks the
  point.
- **SETTLE.** Request zero velocity until `velocity.length() < settle_epsilon` (2 px/s). Then **re-check LOS** from the
  actual position: blocked → BREAK_CONTACT.
- **AIM** (`aim_seconds` 1.3; F4: difficulty may shorten AIM, never LOCK).
  - Velocity request zero (**stationary**, R4.13). `face_toward(lock_point)`.
  - The telegraph tracks `lock_point = TargetInfo.intercept(muzzle, rail_speed).point` (full intercept: "predicts
    further ahead", R4.24) at ≤ `aim_track_rate` (2.0 rad/s), drawn as a **dim red line, width 1**.
  - The barrel unfolds (§2.7). StateLight CHARGING.
- **LOCK** (`lock_seconds` 0.5, F4's 27-frame floor).
  - The lock point freezes. The line turns **bright, width 3, near-white**. StateLight **COMMIT**.
  - Still stationary. This is the dodge window: a 2200 px/s round crosses 900 px in 0.41 s (C8).
  - **LOS is re-checked on the LOCK → FIRE tick.** Blocked → **no round is acquired**, the light drops to OFF, the
    barrel folds, and the sniper goes to BREAK_CONTACT (R4.23).
- **FIRE.** `RailPool.acquire(muzzle)` and `set_direction(lock_dir)`.
  - Spawn a `RailTrail` into the container: a `Line2D` from the muzzle following the round's position until the round
    expires, then fading over 0.4 s on its own counter (no `create_timer`). It holds a weak reference to the round, so a
    recycled round is never read (R4.17).
  - Telegraph off. Barrel folds over 0.3 s. Record `last_bearing`.
- **Assault.** `engage_seconds` 9.0, which is one or two shots.
  - Budget expiry in AIM or LOCK defers DISENGAGE until the shot is fired (deferral ≤ `aim + lock` = 1.8 s). Anywhere
    else it disengages at once.
  - DISENGAGE is the Ph3 exit at `exit_speed` 320.
  - The sniper "leaves the visible corridor, creates a firing offset … re-enters from a different angle" (R4.19) inside
    `inner_rect()`. That rect is the camera's whole pan range, so most firing points in the corridor's upper band are
    off camera, with zero constraint pressure (S7).

**Rail round** (`rail_round.tscn`):
- speed `rail_speed` 2200, damage `rail_damage` 28;
- capsule r 1.5 × h 24; two `Line2D`s (core and glow);
- **no `WorldEnvironment`**: the old scene's own environment is not copied (research §2.6);
- `ProjectileLifetime` 4 s / 2400 px. It joins the round-lifetime sweep through `SniperConfig.rail_speed` and
  `rail_fallback_speed`.

**Telegraph** (`SniperTelegraph`, the sniper's own `Node2D`; C9). It draws in global space from the muzzle toward the
lock point, extended to `max(distance + 300, 900)` px so it reaches past the player when the sniper is off camera (C8).
`SniperAimVisualizer` is shared with the player weapon and is **not touched**.

**Decoy** (R4.18, S16, F6).
- `SniperConfig.decoy_telegraph: bool = false` is the difficulty flag. Ph16 maps a tier onto it.
- When on, SETTLE is followed by **DECOY**: for `decoy_seconds` (0.6) the telegraph draws a dim **orange** line, width 1,
  at a bearing offset of `decoy_offset` (±25–35°, rng) from the player. StateLight CHARGING. Then the line cancels, and
  the real AIM begins.
- The decoy never uses the LOCK colour or width, and never COMMIT (the Ph2 rule: COMMIT is exclusive to a real attack).
- A decoy never fires anything. In the shipped game the flag is off.

**R4.16 windows**, as the player sees them:
- moving (BREAK_CONTACT/RELOCATE): light OFF, barrel folded;
- stationary (SETTLE/AIM/LOCK): red, then white, barrel unfolded;
- escaping (BREAK_CONTACT after FIRE).

### 2.6 Ram Corvette (R4.30–R4.38)

#### 2.6.1 Armour (research A3; X2–X4, X7; C1–C4)

**Scene.**
- An 80–88 px hull. The body `CircleShape2D` is r ≈ 34, shared by the contact box and the root `HurtBox` (default
  `DefenseProfile`, mask 1121).
- A `Plates` node holds `PlateFront`, `PlateLeft` and `PlateRight` (`ArmorPlate` instances). Each sits on the hull rim at
  0° / ±100° from the nose, with its own capsule hurtbox, so a rocket from those arcs meets a plate before the hull's
  centre.

**`RamCorvette`:**
- `is_armored()` → `live_plates > 0`.
- `deflects_hit(hit_box)` → `is_armored()`. On the armoured hull **every** type passes through, rockets included, so
  that rockets reach plates.
- `_on_received_damage(damage)`: while armoured → emit `armor_deflected(damage)`, flash, return. This is the station
  pattern, and it covers the direct emitters (beam, dash, nova, shield overload, engine boost; C2). Otherwise call
  `super`.
- `homing_point(from)` → the global position of the live plate nearest `from`, else `global_position`.
- `is_laser_blocking()` → `is_armored()`. The beam stops at an armoured Corvette and passes once it is exposed. The old
  Ram used the same rule.
- `plate_broken(plate_name: StringName)` and `armor_broken` (last plate) signals.
- Joins group **`enemies`** (S5).

**Changes outside the enemy, all in the armour task (t16):**
- `bullet.gd`: the unlimited-pierce branch drops `or parent.is_in_group("ram_ships")`. The player's sniper shot now
  passes an armoured Corvette (hull deflect) and damages an exposed one (X4).
- `emp_blast_module.gd`: `"RamShip"` → `"RamCorvette"`. EMP immunity is kept; the module's text already says "ram ships
  are immune".
- `engine_boost_module.gd`: `"RamShip"` is **removed** from its immune list. Boost contact is a direct emitter, so the
  hull rule deflects it while armoured and lets it hurt once exposed. "Contact damage does not bypass armour" (R4.36)
  then holds without a class list. This is owner-visible (§8).
- `test_station_reinforcements.gd` case 16: the comment's reason changes. The Corvette's mask is 1121 now. The assertion
  stays as a generic guard.
- `test_ram_ship.gd` → `test_ram_corvette.gd` (intent). `test_defense_profile.gd`'s alternate-mask case moves to a
  fixture (X2). `test_player_bullet_lifetime.gd` gains plate rows.

**Numbers.** Plate HP 50: one rocket of either kind breaks one plate. Hull HP 120. Contact 50 armoured, 60 exposed
(research §3).

**Heavy-weapon stagger** (R4.36, "heavy weapons stagger armour"): a plate breaking during LINE_UP or WIND_UP cancels the
charge. The ship gets `stagger_seconds` (0.4) of no thrust, a StateLight `blink_once()`, then LINE_UP again. Never during
CHARGE: a committed charge is committed. Anything more (per-plate weapons, debris) is Ph10.

#### 2.6.2 Charge (R4.33, R4.35, R4.38, F4, F5)

```
APPROACH → LINE_UP → WIND_UP → CHARGE (incl. overshoot) → WIDE_TURN → LINE_UP …
```

- **APPROACH.** Curved intercept at `cruise_speed` to within `engage_range` (420).
  - **In Assault the approach target is offset sideways** by `assault_side_offset` (240) from the player, toward the side
    the Corvette is on, and above or below it. The charge line is therefore diagonal across the corridor, never a
    vertical dive (R4.35).
- **LINE_UP.** Turn (at the mover's `max_turn_rate` 2.2) until the nose is within 8° of the intercept line.
  - Lead time `t = Steering.clamped_lead_time(d, charge_speed, 0.15, 0.6)`: "a rammer predicts a shorter future
    position" (R4.38).
  - The aim point is `P̂ = predicted_position(t)`, clamped to the inner rect in Assault.
- **WIND_UP** (`wind_up_seconds` 0.65).
  - Brake to a crawl (≤ 30 px/s).
  - Every plate's `set_glow` ramps 0 → 1 (R4.41). StateLight CHARGING.
  - For the first 60 % the aim tracks at ≤ `windup_track_rate` (0.8 rad/s). It then **freezes** (F5).
- **CHARGE.**
  - `mover.boost(dir, charge_speed, (|P̂ − pos| + overshoot) / charge_speed)`, with `overshoot` 220 px. The boost runs
    past the projected point (R4.33). The line is never re-aimed.
  - StateLight COMMIT. Glow stays at 1.
  - Contact is armed (§2.6.3).
- **WIDE_TURN.**
  - `Steering.turn_toward` from the charge heading toward the player at `wide_turn_rate` (1.4 rad/s), at `cruise_speed`.
  - Ends when the heading is within 30° of the player. Then LINE_UP.
  - Glow fades to 0. "It should not instantly die if it misses": a contact never frees it.
- **Exposed** (`armor_broken`):
  - `cruise_speed` 160 → 220, `charge_speed` 620 → 700;
  - `contact_hit_box.damage = exposed_collision_damage` (60);
  - **evasive:** in APPROACH and WIDE_TURN, while the player's facing is within `evade_cone` (20°) of the Corvette and
    `d < evade_range` (600), it adds `Steering.strafe(P, side, evade_speed 180)`, so it jinks out of the player's aim
    line.
  - The light blinks once on the transition.
- **Assault.**
  - `engage_seconds` 4.5, which is one charge.
  - Budget expiry in LINE_UP, WIND_UP or CHARGE defers to the charge's end (deferral ≤ 0.65 + `charge_max_time` 1.2 s).
  - **DISENGAGE continues straight along the charge heading** at `exit_speed` (500) until it leaves the world rect. A
    straight exit is the closest feel to the legacy dive-through, and it gives the cloud_descent deadline its margin
    (§2.9.3).
  - Expiry outside a charge: the nearest-edge exit (Ph3), at `exit_speed`.

#### 2.6.3 `ContactProfile.Mode.ARMOR` (R4.37, X8)

- `ARMOR` is appended to the enum.
- **Armable, and armed at `setup()`.** COLLISION never toggles; RAMMING starts disarmed. While armed the
  `ContactHitBox` is on and every touch emits `contact_made`. It **never detonates**, and never damages or frees its
  owner.
- **The Corvette's rule:**
  - while plates remain, the profile stays armed: "the plates hurt to touch";
  - on `armor_broken` the brain disarms it, and from then on arms it only during CHARGE (RAMMING semantics).
- "Partially protecting the enemy" is the hull rule: dash, boost and nova contact are deflected while armoured.
- The contact-damage gate reads the spawn-time `collision_damage` (50). `test_base_enemy.gd::_AUTHORED_CONTACT_MODES`
  gains `ram_corvette: ARMOR`.
- The rail fallback is the profile itself: on a rail it is armed for life, with nothing to fire.

### 2.7 Visual states and art (R4.41, S10, S12, C16)

Every sprite goes through the `pixel-art-generation` skill: strict top-down (`view: "high top-down"`,
`isometric: false`), saved by `scripts/pixellab.sh`, opened and looked at, and ≤ 90 % opaque. Each sprite gets several
candidates and the best is refined (CLAUDE.md: use the allowance). The look is IDEAS §21: dark hull, a cool edge light,
a red faction stripe, and **one** gameplay light (the `StateLight`). All are drawn **nose-down**
(`sprite_forward_angle` `PI/2`). All use a `Sprite2D` named `Sprite2D`, so `BaseEnemy._rotate_sprite()` does not flip
them. `test_base_enemy.gd`'s flip list loses `ram_ship` in t16.

| Enemy | Assets | Visual state wiring (in the behaviour task) |
|---|---|---|
| Bomber | `bomber.png` ≈ 104 × 56, **wide**, with bay doors read in the silhouette | Ordnance is code-drawn. A mine's red armed blink and a bomb's warning blink are in t6. |
| Sniper | `sniper.png` ≈ 40 × 60 hull, **narrow**; `sniper_barrel.png` ≈ 8 × 40 | `Barrel` scale.y 0.35 → 1.0 and its offset ease out over the first 0.4 s of AIM (brain clock), and fold back over 0.3 s after FIRE or a refusal: "weapon unfolds during charge" |
| Ram Corvette | `ram_corvette.png` ≈ 84 × 84 hull, with no plates painted on; `ram_plate_front.png`, `ram_plate_side.png` (mirrored for the left plate) | `ArmorPlate.set_glow` during WIND_UP/CHARGE; break = hide + burst + free, "physically disappear". The hull sprite never changes colour. |

Until each art task lands, the shell task uses placeholders (the legacy PNGs; plates as `Polygon2D`s). The art task
swaps textures only, and no scene structure changes.

### 2.8 Rails (X10)

`suspend_ai()` (a rail) stops the brain. Each enemy's `on_suspended()` installs a legacy-equivalent fallback, so every
interim build (shell landed, level 1 not yet migrated) plays like today. `level_2_waves.gd` keeps working the same way.

- **Bomber.**
  - A root `_process` clock, active only while `is_ai_suspended()`, drops a gravity bomb every `rail_bomb_interval`
    (1.2 s), launched `Vector2.DOWN` at `rail_bomb_speed` (120). This is today's bomb.
  - Root scripts may run a clock: nothing writes motion.
- **Sniper.**
  - `SniperTelegraph.start_rail_cycle(...)` runs its own `_process` cycle at the legacy timings: `rail_aim_seconds` 2.0
    tracking at 4.0/s, `rail_lock_seconds` 0.5. It then fires a rail round at `rail_fallback_speed` (1400, today's
    shot) toward the locked point, up to `rail_shot_count` (5) shots.
  - It **never writes the ship's rotation**. The path mover owns rotation on a rail, which retires today's two-writer
    conflict.
- **Ram.** ARMOR contact is armed for life. Plates and the hull rule work unchanged on a rail.

### 2.9 Level 1 migration (R4.42, C5, C11–C14, S6, S14)

#### 2.9.1 Pin first (t1), with frozen legacy baselines

`tests/integration/test_level1_specialist_spawns.gd`:
- **Pins all 50 rows** (26 sniper, 22 ram, 2 bomber): section, trigger, offset and delay, counted from data in the
  `test_level1_fighter_spawns.gd` shape. Fire timing is **not** pinned (C14).
- **Freezes** `_LEGACY_PEAK_SPECIALISTS` per section: the peak alive count of these three families, computed from the
  live rails with `level1_drone_concurrency.gd`'s machinery. The test asserts the constant equals the live computation
  until that section is migrated, as Ph3 did.

#### 2.9.2 DURATION sections (t21): deep_space and planet_approach

- Every sniper, ram and bomber line loses `.move()`, `.free_after()` and `shoot_*()`. Trigger, offset and delay are
  unchanged (the pin).
- `free_after` values are dropped. The config budget replaces them: sniper 9.0 s, ram 4.5 s, bomber 8.0 s.
- The pin becomes "no `.move()` on any of the 50 rows".
- **Count gate:** per section, peak alive specialists (from `ai_shooter_kinds()`-style lifetimes for the three:
  `entry + engage + deferral + exit`) ≤ **2.5×** `_LEGACY_PEAK_SPECIALISTS`.
- **Pre-approved levers**, in order, used only if the gate fails:
  1. ram `engage_seconds` 4.5 → 3.5;
  2. sniper 9.0 → 6.0 (one shot);
  3. bomber 8.0 → 6.0.

  Still over → stop with `Result: ESCALATE` for an owner decision. Do not move triggers.
- **Boundary:** a ram line given `.move()` again fails the pin. One extra ram triple at planet_approach's peak fails the
  count gate.

#### 2.9.3 cloud_descent (t22): the ENEMIES_CLEARED section

- The 9 snipers and 6 rams come off rails. `test_engagement_deadline.gd` gains **per-entry rows** with the Ph3 formula:
  `(entry − 76.0) + engage + deferral + worst_exit + 0.5 < 10.0`.
  - **Sniper:** deferral = `aim + lock` (1.8). The exit is a curved bound measured on the real `sniper.tscn` (the Ph3
    404-start probe).
  - **Ram:** deferral = `wind_up + charge_max_time` (1.85). The exit is the straight-line bound: the world rect's
    diagonal / `exit_speed` (2274 / 500 ≈ 4.55 s [estimate]), plus the measured nearest-edge bound for an expiry outside
    a charge. The task uses the larger.
- **The 73.2 s ram is the tight row:** 4.5 + 1.85 + 4.55 + 0.5 = 11.4 against an allowed 12.3 [estimate]. That is 0.9 s
  of margin.
  - Pre-approved levers: ram `engage_seconds` → 4.0, then `exit_speed` → 560.
  - The 63.2 s snipers allow 22.3 s: 9.0 + 1.8 + ≈ 4 + 0.5 ≈ 15.3 [estimate].
- **Boundaries:**
  - a ram at 76.0 s with delay 1.2 computes over 10 and fails;
  - **no ENEMIES_CLEARED section contains a Bomber**, with a row showing a bomber in cloud_descent's last wave would fail.
    Its persisted mines would hold the section open (C5). This is the Gatling precedent.
- **Real replay:** `test_level1_fighter_exit.gd` already contains the 72 s ram. It must still empty within the timeout
  with the ram on AI. A specialist variant asserts the same with the snipers and rams only, and prints the measured
  margin.

### 2.10 Open Space hub (R4.43, S13)

- **Hub idle** (t19): the Ph3 "minimal idle" for all three brains. `AnchorIdle` (perceive / lose / notice / home) and a
  slow orbit of `idle_radius` (150) around `patrol_anchor`.
  - IDLE never drops, aims or charges.
  - RETURNING never interrupts a RUN, an AIM/LOCK or a CHARGE (Ph3 deviation 15).
  - Perceive radii: Bomber 650, Sniper 700, Ram 600.
  - In Assault the brain starts in combat.
- **Spawn** (t20): `SectorHub._spawn_patrol()` appends, **after the four existing draws** so their seeds do not move,
  one Sniper at 135°, one Bomber at 45° and one Ram Corvette at 225°, on `specialist_ring_radius` 1700 [estimate].
  315° stays free: it is the closest diagonal to the pickup bench (research §3.1).
  - `test_sector_hub_patrol.gd` gains a clearance row per group, computed on the real scene: `d − idle_offset >
    perceive_radius` for every `MissionTrigger`/`PickupBase` and the spawn point, plus anchors > 1000 px apart.
  - The task may raise the ring if the live sweep says so. Ph2's t16 had to.
- **Ordnance in the hub** lands in `EnemyContainer` (the pool's grandparent) and expires on its own lifetime. There is
  no world rect in Open Space.

### 2.11 Mode compatibility and the §43 checklist (R4.40, R4.46)

Every behaviour spec runs in both harnesses (`use_parameters(["open_space", "assault"])`, label-parameter shape only),
with assertions stated relative to the constraint. The checklist questions, answered by the design rather than by an
audit (the audit is Ph17):

| Question | Bomber | Sniper | Ram Corvette |
|---|---|---|---|
| Player approaches from behind | Its next line is planned from the player's path, not its own heading. It escapes on the arc. | BREAK_CONTACT picks the side away from the player's line | WIDE_TURN, then LINE_UP from wherever it is |
| Player boosts away | The lead is damped and boost is not fully led (F9). Mines are laid across the new path. | Re-picks its point in the new player frame. It can be caught; that is the counterplay. | The clamped lead is short, so a boost escapes a committed charge |
| Fights off-screen | Ordnance persists; the line can be off camera | Yes: firing points beyond the half-view, with the telegraph long enough to reach | Yes: the charge starts from wherever it lines up |
| Distinct telegraph | Angled lead-in + red light + mine blink | Dim line → bright line + barrel + white light | Plate glow + yellow light → white |
| Testable deterministically | Seeded rng; jitter 0 in tests | Seeded candidates; bearing separation asserted as an angle | Clamped lead; direction asserted by angle |

---

## 3. Build sequence

Each step is one task in `tasks.json`, under the same key.

1. **`t1-pin`** (test): §2.9.1. Runs first, because every later task edits what it pins.
2. **`t2-break-contact-los`**: §2.2.1 and §2.2.2. `Steering.break_contact` and the mover wrapper; `LineOfSight`; the real
   `TargetInfo.line_of_sight`; the stub assertions replaced.
3. **`t3-persist-pool`**: §2.2.3, the `BulletPool` flag, and the `ProjectileLifetime` doc.
4. **`t4-armor-query`**: §2.2.4. `ArmorQuery`, the three projectile call sites, `homing_point`, and the `ArmorPlate`
   component, tested on a fixture armoured entity. The station is unchanged.
5. **`t5-contact-armor`**: §2.6.3, `ContactProfile.Mode.ARMOR` with unit cases.
6. **`t6-ordnance`**: §2.3. `EnemyOrdnance`, the three scenes, `EnemyOrdnanceScenes`, and the lifetime-sweep rows,
   proven with a fixture dropper.
7. **`t7-rename-ram`**: `git mv` `ram_ship/` → `ram_corvette/`; the classes; every roster; `WaveBuilder.RAM`; both
   module immune lists renamed to `RamCorvette` (behaviour-neutral). No behaviour change.
8. **`t8-rename-sniper`**: `git mv` `sniper_enemy/` → `sniper/`; `SniperEnemy` → `Sniper`; rosters; `WaveBuilder`;
   `test_enemy_bullet_lifetime.gd`'s references. No behaviour change.
9. **`t9-bomber-shell`**: §2.4 scene, `BomberConfig` (flat, every field above), the three pools with
   `persist_after_owner_death`, a minimal `BomberBrain` (phase enum + seam, APPROACH as a plain intercept, the Assault
   budget and DISENGAGE, no drops yet), and the §2.8 rail fallback. `bomb.gd/.tscn` deleted. Dual-mode entry added.
10. **`t10-bomber-runs`**: §2.4 items 1–7 (prediction, choice, line, Dubins approach, RUN drops, escape, reposition) and
    the dual-mode placement specs.
11. **`t11-art-bomber`**.
12. **`t12-sniper-shell`**: the §2.5 scene, the new `SniperConfig`, the rail round and pool, `SniperTelegraph`
    (including the §2.8 rail cycle), placeholder barrel, a minimal brain (ENTER + budget + DISENGAGE), `FLY_IN_TIME` and
    `_process` removed, `enemy_sniper_bullet.tscn` deleted, and the lifetime sweep moved to the rail round's config
    fields.
13. **`t13-sniper-cycle`**: the §2.5 cycle, the firing-point selection, LOS gating, `RailTrail`, barrel unfold, and the
    dual specs.
14. **`t14-sniper-decoy`**: the §2.5 decoy behind `decoy_telegraph`.
15. **`t15-art-sniper`**.
16. **`t16-ram-armour`**: the §2.6.1 scene (plates, hull rule, `enemies` group, `homing_point`, `is_laser_blocking`), the
    ARMOR profile wired in, a minimal brain (APPROACH + budget + DISENGAGE), and every outside change listed in §2.6.1.
    Plate-by-plate tests with real bullets and rockets.
17. **`t17-ram-charge`**: §2.6.2 (LINE_UP, WIND_UP + glow, CHARGE + overshoot, WIDE_TURN, stagger, exposed stats and
    evasion, Assault diagonal, Assault straight exit) and the dual specs.
18. **`t18-art-ram`**.
19. **`t19-specialist-idle`**: §2.10 hub idle for all three brains.
20. **`t20-hub`**: §2.10 spawn and clearance rows.
21. **`t21-level1-duration`**: §2.9.2.
22. **`t22-level1-cloud`**: §2.9.3.
23. **`t23-docs`**: the `updating-project-docs` skill. Three `ENEMY.md` files, `docs/enemy-roster.md`,
    `assault.md` / `global.md` / `PROJECT.md`, `docs/BULLET_POOL.md` (the flag), and the CLAUDE.md conventions:
    - the bullet-deflect paragraph gains `deflects_hit` / `ArmorQuery`;
    - the gate list gains the specialist pin and deadline rows.

    Also DECISIONS *as built* and the dossier.

**Dependencies:**
- Roots: t1, t2, t3, t4, t5. t6 needs t3 (pooled ordnance hands over).
- **t7 needs t1. t8 needs t1 and t7.** Both edit the same rosters (contact damage, contact geometry, hurtbox geometry,
  `test_base_enemy.gd`, config isolation), so they run in series.
- t9 needs t3, t6 and t1. t10 needs t9. t11 needs t9.
- t12 needs t8. t13 needs t12 and t2. t14 needs t13. t15 needs t12.
- t16 needs t4, t5 and t7. t17 needs t16. t18 needs t16.
- **t9, t12 and t16 all add a case to `test_enemy_dual_mode.gd` and rows to the gates**, so they run in series: t12
  needs t9, and t16 needs t12.
- t19 needs t10, t13 and t17. t20 needs t19.
- t21 needs t1, t10, t13 and t17. t22 needs t21.
- t23 needs t11, t14, t15, t18, t20 and t22.

---

## 4. Test plan

**Bold** cases are boundaries. "Dual" means the case runs in both harnesses. Angles are compared with
`angle_difference` and vectors with `assert_almost_eq`. Every new test file is GUT, extends `GutTest`, and follows
`tests/README.md` (the `user://` sandbox, signal arity, and no abandoned harness nodes).

| File (task) | Cases |
|---|---|
| `test_level1_specialist_spawns.gd` (t1; updated t7, t8, t21, t22) | The 50 pinned rows equal the live ones (section, trigger, offset, delay), counted from data. `_LEGACY_PEAK_SPECIALISTS` equals the live rail computation per unmigrated section. **A row with a changed delay fails. A missing row fails.** After t21/t22: no `.move()`, `free_after` or `aim_mode` on any row, and the count gate ≤ 2.5×. **An extra ram triple at the peak fails the gate** |
| `tests/unit/test_steering.gd` (t2, extended) | `break_contact`: distance to a stationary threat grows every step over 2 s of integration. The returned speed equals `max_speed`. `side` +1 / −1 mirror the lateral component. **A closing threat roughly doubles the lateral share against an opening one.** **Zero distance returns a finite vector of `max_speed` length** |
| `tests/unit/test_line_of_sight.gd` (t2, new) | Each case awaits one physics frame after placing bodies. A `StaticBody2D` in group `asteroids` on the segment → blocked. Removed → clear. **A plain `CharacterBody2D` (a fighter stand-in) on the segment → clear (opt-in rule).** A body answering `blocks_line_of_sight() == true` → blocked. A blocker behind the target → clear. An excluded RID → clear. **Five non-blocking bodies stacked on the line still return (cap reached → clear) without hanging** |
| `tests/unit/test_target_info.gd` (t2) | The stub assertions are replaced: `line_of_sight` is false with no target, and delegates to `LineOfSight` with a target |
| `tests/unit/test_bullet_pool.gd` (t3, new) | Flag off: freeing the owner frees in-flight bullets (today's behaviour, pinned). **Flag on: freeing the owner leaves the in-flight bullet in the container and live; its `expired` frees it; it never returns to a pool.** **The bullet emits `expired` in the same frame the owner is freed (deferred recycle already queued): no error, freed exactly once.** `cancel_active()` still frees everything with the flag on. The idle bullets are freed with the pool |
| `tests/integration/test_armor_query.gd` (t4, new) | On a fixture entity (hull `is_armored` + one `ArmorPlate`). **A real player bullet crossing the plate is not consumed (it reaches a stub behind it) and the plate's Health is unchanged.** `deflected` fires once. A real warhead rocket hitting the plate breaks it (`broken` fires, the hurtbox closes, the node frees) and the rocket is consumed. A homing rocket locked on the fixture steers to `homing_point()`, and **one fired from behind the hull meets the plate instead of parking at the centre (position after 2 s ≠ centre ± 4 px; plate broken)**. A target with only `is_armored()` behaves exactly as before (station-shaped fixture). **`test_space_station.gd`, `test_station_incoming_damage_paths.gd` and `test_player_bullet_lifetime.gd` pass unedited** |
| `tests/unit/test_contact_profile.gd` (t5, extended) | ARMOR starts armed (the hitbox monitorable after the deferred set). A touch emits `contact_made` and never `detonated`. `set_armed(false)` closes it. **ARMOR's owner dying never detonates.** The existing modes' cases are unchanged |
| `tests/integration/test_enemy_ordnance.gd` (t6, new) | For each kind via a fixture dropper: a player-hurtbox stub inside `trigger_radius` → warning → **exactly one** `ContactBlast` with the configured radius and damage after the fuse. **A player bullet defuses it: no blast, `expired` once.** A mine is stationary after its 0.3 s ejection (drift < 1 px over 2 s) and fizzles at `mine_life` with no blast. **A pursuit bomb's heading after its steer window is frozen (a target moved afterwards does not change it); a player turning at full rate escapes it (closest approach > trigger radius).** A gravity bomb keeps its launch direction. **No `Timer` child and no `create_timer` call in `enemy_ordnance.gd` (a source sweep).** Ordnance is not in `enemies` |
| `test_enemy_bullet_lifetime.gd` (t6, t12) | The sweep gains rows for the gravity bomb and pursuit bomb (config speeds), the mine (time-bound only), and the rail round (`rail_speed`, `rail_fallback_speed`). **A synthetic 50 px/s ordnance with the 12 s / 1800 px caps fails.** `enemy_sniper_bullet.tscn` rows are removed with the scene (t12) |
| Renames (t7, t8) | Every invariant gate is green with the renamed rosters. `test_ram_ship.gd` / sniper tests still pass under the new paths. **EMP still skips the renamed ram (immune list follows the rename).** The t1 pin is green |
| `tests/integration/test_bomber.gd` (t9) | Pools are root children with the flag on, sized ≥ `pool_size_for`. Rail: `suspend_ai()` → a gravity bomb every 1.2 s ± a tick, moving `DOWN` at 120, from config. Assault DISENGAGE at `engage_seconds` frees it outside the world rect. **Killing a bomber on a rail with a bomb in flight leaves the bomb live** |
| `test_bomber.gd` (t10, extended), dual | **Placement against the predicted path (R4.40):** player stub at constant v = (220, 0). Every mine's rest point lies within 40 px of the line through `P̂` ⟂ `v̄`, and the mines' centroid is ≥ 100 px closer to `P̂` than to the player's position at drop time. **Stationary player → line through P.** Gravity bomb: its travel ray passes within 30 px of `P̂`. Pursuit: launched toward `P̂` ± 10°. **Assault: with the player 60 px from the right wall moving right, every rest point is inside `inner_rect().grow(−64)`.** The choice rule across three setups (fast → MINE, close+slow → GRAVITY, far → PURSUIT) with jitter 0. The approach arrives within 15° of the line's heading. ESCAPE: the heading turns at ≤ `escape_turn_rate` + ε and the distance to the player grows through ESCAPE. **Budget expiry mid-RUN finishes the run first** |
| `tests/integration/test_sniper.gd` (t12) | Scene shape, `SniperConfig` applied (HP 60, contact 20). **No `FLY_IN_TIME` symbol anywhere in the project (sweep).** Rail cycle: aim 2.0 / lock 0.5, a rail round at 1400 within 2.6 s ± a tick of `suspend_ai()`, and **the sniper's `rotation` is never written by its own scripts on a rail (the single-writer gate stays empty)**. Assault DISENGAGE |
| `test_sniper.gd` (t13, extended), dual | **New firing position every cycle:** over 3 cycles, consecutive firing bearings (player frame) differ by ≥ 45°. **Corner boundary (Assault, player in a corner): the next point is legal (inside the grown rect) and the fallback path is taken only when no ≥ 45° candidate exists.** **Stationarity:** from SETTLE end to the shot, `velocity.length() < 2` every tick and drift < 1 px. **Post-shot disengage:** distance to the player strictly increases over the 1.0 s after FIRE, and no tick in that second has a velocity component toward the player > 0. **LOS refusal:** an `asteroids` blocker placed on the line during AIM (one physics frame awaited) → no round acquired, state leaves LOCK for BREAK_CONTACT, the light is not COMMIT afterwards. Blocker removed → the next cycle fires. **A fighter body on the line does not block.** The lock point equals `intercept(muzzle, rail_speed).point` at LOCK entry. COMMIT is shown only in LOCK. The barrel's scale is 1.0 in LOCK and < 0.5 in RELOCATE. `RailTrail` exists after FIRE and is gone within 0.4 s + 2 ticks of the round expiring. **Budget expiry in AIM defers DISENGAGE until the shot is fired (≤ 1.8 s)** |
| `test_sniper.gd` (t14, extended) | Flag off: no DECOY state ever (sweep over 3 cycles). **Flag on: DECOY precedes AIM, its line bearing is ≥ 25° from the player, the light is CHARGING (never COMMIT), and no round is acquired during it.** Dual |
| `tests/integration/test_ram_corvette.gd` (t16; replaces `test_ram_ship.gd`), dual | **Plate-by-plate vulnerability (R4.40):** real bullets at the hull and each plate are not consumed and deal 0 (hull Health unchanged, `armor_deflected` emitted). A real warhead rocket at each plate in turn breaks that plate only. **After 2 plates the hull still takes 0 from bullets. After the 3rd, a bullet reduces hull Health by its damage.** `is_armored()` follows. Front, side and rear rocket approaches each break a plate (C4). The beam (direct emit) deals 0 while armoured and is blocked; it hurts when exposed. **The player's sniper shot passes an armoured Corvette without stopping and damages an exposed one.** Group `enemies`. ARMOR contact armed at spawn. **Engine boost contact deals 0 while armoured and damages when exposed. EMP still skips it** |
| `test_ram_corvette.gd` (t17, extended), dual | **Charge direction (R4.40):** the CHARGE velocity points at `predicted_position(clamped_lead)` captured at the WIND_UP freeze, within 5°. **A player moving after the freeze does not change the charge heading.** The WIND_UP lasts 0.65 s ± a tick with speed ≤ 30 and glow rising to 1. It travels ≥ 200 px past the projected point (overshoot). **A missed charge leaves it alive, and WIDE_TURN's heading change per tick is ≤ `wide_turn_rate`·dt + ε.** Contact is armed during CHARGE when exposed and disarmed otherwise. **A plate broken during WIND_UP cancels the charge (stagger), and one broken during CHARGE does not.** Exposed: charge speed 700, contact damage 60, and the evasive lateral speed relative to the player's aim line is > 0 when aimed at and 0 when not. **Assault: with the player at corridor centre, the charge heading is ≥ 20° off vertical.** Budget expiry in WIND_UP defers to the charge end, then it exits straight along the charge heading |
| `test_bomber.gd` / `test_sniper.gd` / `test_ram_corvette.gd` (t19) | Hub idle: no drop, aim or charge while IDLE. NOTICING → combat inside `perceive_radius`. RETURNING beyond `lose_radius`. **RETURNING never interrupts RUN / AIM-LOCK / CHARGE.** Assault starts in combat |
| `test_sector_hub_patrol.gd` (t20, extended) | The three new groups clear every clearance point by `perceive_radius` + idle offset. Anchors > 1000 px apart. **The four existing groups' seeds are unchanged by the append.** A mine dropped in the hub lands in `EnemyContainer`. **A pickup moved inside the sniper's reach fails** |
| `test_engagement_deadline.gd` (t22, extended) | Per-entry sniper and ram rows for cloud_descent. **A ram at 76.0 s + 1.2 s fails. A bomber in any ENEMIES_CLEARED section fails. No ENEMIES_CLEARED section contains the Bomber scene.** Curved sniper exit measured on the real scene |
| `test_level1_fighter_exit.gd` / new `test_level1_specialist_exit.gd` (t22) | The real `WaveManager` cloud_descent run empties within the timeout with rams and snipers on AI. Margin printed |
| Invariant gates (t6–t18) | Contact damage, contact geometry, hurtbox geometry (each new scene in its ROSTER, completeness sweeps), config isolation (`SniperConfig` added, one `*config*.tres` per directory), single writer (empty allowlist), signal arity, sprite transparency, UID integrity, project load integrity, collision layer names. All green. `scripts/check-test-leaks.sh` is clean after every task that awaits |

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| **Player-weapon regression** from the `ArmorQuery` / `homing_point` edits: they touch all modes and the boss | Additive duck types; the station implements neither; t4's acceptance is the three station/bullet suites passing **unedited** |
| A plate's capsule and the hull's circle overlap. A bullet crossing a plate also crosses the hull | Both deflect a bullet (by design). Tests assert the bullet survives both. A rocket that hits the hull first passes through to a plate |
| Homing rockets lock the root and arrive from any bearing; from behind, a rocket crosses the hull to the far plate | `homing_point()` picks the nearest plate. The rear approach is a test row |
| **Persisted mines** pile up in DURATION sections if bombers die often | `mine_life` 8 s and at most 5 per run. The count is visible in the t21 run. ENEMIES_CLEARED sections are barred to Bombers (C5) |
| `_hand_over_active` racing a deferred `_recycle` | Explicit test row (t3); `_recycle` ignores bullets it no longer owns |
| **LOS ray outside the physics step** | Called only from the brain's tick (physics). Tests await a physics frame (C7, F12) |
| Sniper stationarity broken by braking residue or corridor pressure (C10) | SETTLE waits for < 2 px/s. Firing points lie inside `inner_rect().grow(−96)`, where the constraint is identity |
| **Level-1 density** grows (C13): rams lived about 2 s on a rail and now about 9 s | Frozen baseline, a 2.5× gate and pre-approved levers. An Assault ram exits straight. Beyond the levers → escalate |
| **cloud_descent deadline**: the 73.2 s ram | Straight exit; an estimated 0.9 s margin; two pre-approved levers; a real replay |
| The Corvette joins `enemies`: homing rockets and AI targeting now spend shots on it | Intended (S5); flagged for the owner (§8). Rockets breaking plates is the designed counterplay |
| **Gameplay feel cannot be seen by the gate**: whether the decoy-free sniper is fair at 2200 px/s, and whether mines read on dark backgrounds | LOCK ≥ 0.45 s (F4); bright armed blink. Recorded as a known gap for the owner's playtest |
| Art: three ships plus a barrel and two plate sprites | Separate art tasks; placeholders keep the scene structure fixed |
| The legacy sniper's two rotation writers on a rail (C9 at the scene level) | Retired in t12: the rail cycle draws and fires without writing rotation |

---

## 6. Requirements coverage

| Requirement | Task(s) | Note |
|---|---|---|
| R4.1 Bomber size, wide | t9, t11 | |
| R4.2 Angled approach, line, escape arc | t10 | |
| R4.3 Three ordnance types, selected by behaviour | t6, t10 | |
| R4.4 Ordnance shootable | t6 | Defuse, no blast |
| R4.5 Smart bombing on the predicted path | t10 | |
| R4.6 Assault clamp to the corridor | t10 | |
| R4.7 Scrap fixed-screen movement (§38) | t9, t10, t21 | |
| R4.8 Bomber verb | t10 | §2.4 |
| R4.10 Sniper size, narrow | t12, t15 | |
| R4.11 Preferred distance, create distance first | t2, t13 | |
| R4.12 Varied firing offsets, never repeated, LOS-aware | t13 | |
| R4.13 Stationary at the firing point | t13 | |
| R4.14 Telegraph + lock on the predicted point | t12, t13 | |
| R4.15 Fire, then break contact; no return loop | t13 | |
| R4.16 Readable windows | t13, t15 | |
| R4.17 Rail shot + residual trail | t12, t13 | |
| R4.18 Decoy behind a difficulty flag | t14 | Tier mapping is Ph16 |
| R4.19 Assault off-screen band | t13 | Inside `inner_rect()` (S7) |
| R4.20 / §31 Remove `FLY_IN_TIME` | t12 | |
| R4.21 / §38 Scrap path-authored retreat | t13, t21, t22 | |
| R4.22 / §3.2 `break_contact` | t2 | |
| R4.23 / §28 Real `can_see_player()` | t2, t13 | Shipped blockers: asteroids only (S9) |
| R4.24 Sniper predicts further ahead | t13 | Full intercept |
| R4.25 Sniper verb | t13 | |
| R4.30 Ram size | t16, t18 | |
| R4.31 Three plates, rockets break them | t4, t16 | |
| R4.32 Exposed: vulnerable, faster, harder, evasive | t17 | |
| R4.33 Charge telegraph, overshoot, wide turn, survives | t17 | |
| R4.34 Rocket / primary / dodge choice | t16, t17 | |
| R4.35 Assault diagonal charge | t17 | |
| R4.36 / §13.1 Armour deflection rule | t4, t16 | "Heavy weapons stagger" = the charge cancel (t17) |
| R4.37 / §16 Armour contact profile | t5, t16, t17 | |
| R4.38 Ram verb; shorter prediction | t17 | |
| R4.39 / §12 `persist_after_owner_death` | t3, t6, t9 | Pulled forward from Ph5 (X1) |
| R4.40 / §40 Behaviour tests in both harnesses | t10, t13, t14, t16, t17 | |
| R4.41 / §21–23 Sprites and visual states | t11, t13, t15, t17, t18 | |
| R4.42 Level-1 migration | t1, t21, t22 | |
| R4.43 Hub ambient spawn | t19, t20 | |
| R4.44 / §41 Phase 3 items 1–3 | all | Items 4–5 → Ph5 |
| R4.45 Difficulty: "relocates sooner, more varied angles" | — | **Later phase 16.** Only the decoy flag is in scope. `aim_seconds` and `min_bearing_change` are the config levers Ph16 will drive |
| R4.46 §43 checklist | t10, t13, t17 | §2.11; the audit itself is Ph17 |
| R4.47 Bonus Drone unchanged | — | Out of scope (§38 keeps it) |
| §5.6 "fighters flank while the sniper marks" (§18 messages) | — | **Later phase 14** (squad messages) |
| §18.6 "sniper hides behind wreckage" | — | **Later phases 6 / 19** (wrecks, LOS for heavies). LOS is real now, so they plug in through `blocks_line_of_sight()` |
| Mine Layer, minefields, other mine variants (§6.3, §6.9) | — | **Later phase 7.** The Bomber's mine is a single proximity kind |
| Enemy rockets (§11.2) | — | **Later phase 5**, building on X1 |

---

## 7. Out of scope

- Difficulty tiers (Ph16). Squad messages: a sniper marking for fighters (Ph14). Wrecks and other LOS blockers in
  shipped content (Ph6, Ph19). Mine families and the Mine Layer (Ph7). Rockets and owner-distance lifetime (Ph5). The
  Heavy Shell's consumer (Ph10).
- Modular damage beyond three plates (Ph10 builds on `ArmorPlate`).
- Taking the station's reinforcements off rails (Ph15; they never use these three).
- `level_2_waves.gd` migration. The scene is unreferenced, and the rail fallbacks keep it working.
- Enemy audio and muzzle VFX (Ph17).
- The Bonus Drone.
- The legacy homing-rocket "park at the station core" behaviour. The station implements no `homing_point`. Recorded
  as a follow-up for Ph11 (Space Fortress 2.0), not changed here.

---

## 8. Open questions for the owner (not blocking; the plan takes the stated default)

1. **Shot ordnance defuses (no blast)**, rather than detonating where it is. Default: defuse. Alternative: a reduced blast,
   which would let the player detonate mines on enemies. That needs friendly-fire rules, which do not exist.
2. **Engine-boost immunity for the Corvette is removed** (the hull rule protects it while armoured). **EMP immunity is
   kept.** Both are owner-visible.
3. **The Corvette joins `enemies`.** Homing rockets, AI targeting, the beam, dash, nova and shield overload now see it. All
   except rockets on plates are deflected while it is armoured.
4. **The player's sniper shot no longer stops on rams.** It passes armour and damages an exposed hull.
5. **Mines outlive their Bomber** (the scope's choice over a kill-cancel, F10).
6. **Level-1 specialists live for a budget** (sniper 9 s, ram 4.5 s, bomber 8 s) instead of a rail's few seconds. Rams now
   take one charge each, and the shipped "missile target" role is preserved by the plates.
