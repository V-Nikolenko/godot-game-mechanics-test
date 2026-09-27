# Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles — plan

Epic `cmufs7ek60001nm2x6d0bt2et`, plan task `cmufs7ekl0009nm2x5rh6gubn`, 2026-09-27. Revision 1.

Built on `1-context.md` (code facts, requirement ids `R2.1`–`R2.24`, gate table) and `2-research.md` (scope check
`S1`–`S11`, findings 1–9, risks `C1`–`C11`), both beside this file. It is not re-derived here. It also builds on the
idea's decision log `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (Phase 1 plan and *as built*) and on
`docs/epics-done/cmufklb100001p92xs1ey2fb1/REPORT.md`. Where this plan changes a Phase 1 decision, §2.0 says so.

Values marked **[judgement]** have no citable source. They are starting defaults, set in `.tres` configs so they can be
tuned without code changes. Symbols are cited instead of line numbers because line numbers drift.

---

## 1. Problem (player-facing)

Today:
- **Kamikaze Drones** in Assault fly fixed straight or sine rails. Each one locks its heading once at spawn, so one
  sidestep beats a whole group.
- The **Drone Interceptor** is the only enemy that hunts in 2D. It has one trick: orbit, then an un-telegraphed
  suicide dash. Once you learn "dodge when it stops circling", it is harmless.
- **Open Space** has three grey squares that drift in straight lines forever (`PatrolDrone`). They never attack and do
  not look like ships.

After this phase:
- **Swarm Drones** (small, cheap, 32 px) fly as a *group*. One drone leads the attack, two cut in from your left and
  right, and the rest circle behind you and wait. The lead winds up visibly (a yellow light), then rams where you are
  *going* (a red light while it is dangerous). If it misses, it overshoots, swings round and tries once more. When the
  lead dies, another drone takes its place.
- The **Razor Drone** (48 px) is what the Drone Interceptor becomes. It circles you, sometimes reverses direction, and
  sometimes fakes a dash: it winds up, brakes, slides past and attacks from the other side. Only the real dash shows
  the white "commit" flash. It survives a miss, fires one pulse shot at you, and comes round again.
- Touching a drone only hurts **while it is attacking** (its red light is on). A Swarm Drone that hits you explodes.
  Shooting one point-blank while it is armed sets off its blast.
- In **Open Space** the hub has a Swarm squad and a Razor Drone idling on patrol around the hub, out of reach of where
  you spawn. Fly close and they notice you, turn and fight.
- In **Assault level 1**, the drones arrive at the same moments and places as before. They then fight inside the
  corridor instead of flying a rail, and leave after a short engagement so the level's pacing holds.
- The **Bonus Drone** does not change.

---

## 2. Design

### 2.0 Changes to earlier decisions, stated explicitly

| # | Phase 1 decision (DECISIONS.md) | Change | Why |
|---|---|---|---|
| D1 | L11 roadmap: Explosive collision in Ph7 | Built **here**, used by the Swarm Drone | Phase scope names it (research S1). Ph7 reuses it |
| D2 | §18.5 idle profiles → Ph14 | The **generic** anchor-idle → combat handover (`AnchorIdle`) and the Razor idle are built here. Other families' idle profiles stay in Ph14 | Phase scope (S2). Ph14 builds on this contract |
| D3 | Assault migration → Ph15 | Only level-1 Kamikaze/Interceptor spawns and the station's two BOTTOM drones move now. Everything else stays on rails until Ph15 | Phase scope (S3) |
| D4 | P-18: make `BulletPool`'s grandparent container injectable in Ph2 | **Not done.** A test pins that the Razor's pulse lands in the hub's `EnemyContainer` | Every real parent chain already satisfies pool → ship → container (S7). Churning seven pool users buys nothing yet. It stays open for Ph5 (owner-bound projectiles) |
| D5 | Interceptor pins "1:1 with pre-port" | Retired and rewritten as Razor pins. The corridor is turned **on** (`constraint_mode = AUTO`) | DECISIONS already said Ph2 re-pins (S9) |
| D6 | Legacy dash cull via `EnemyWorld.cull_rect()` | Assault AI drones exit through **`EnemyWorld.projectile_world_rect()`** (it covers every camera pan) after a released constraint. `cull_rect()` stays for legacy users | The cull rect is fixed to the camera's pinned position and ignores `offset`, so a live drone could vanish while visible. The Interceptor never hit this because it was always off-screen and dashing (§2.6) |

### 2.1 Where things live

| Thing | Path | Kind |
|---|---|---|
| New steering primitives | `global/enemy_ai/steering.gd` (`Steering`) | pure static additions |
| `ContactProfile` | `global/components/contact_profile.gd` | `Node` child of an enemy, mirrors `DefenseProfile` |
| `SquadController` | `global/enemy_ai/squad_controller.gd` | `RefCounted` role board |
| `AnchorIdle` | `global/enemy_ai/anchor_idle.gd` | `RefCounted` helper owned by a brain |
| `EngagementBudget` | `global/enemy_ai/engagement_budget.gd` | `RefCounted` helper owned by a brain |
| `StateLight` | `global/components/state_light.gd` | `Node2D` presentation child (`Sprite2D`-based) |
| Swarm Drone | `assault/scenes/enemies/swarm_drone/` (`swarm_drone.tscn/.gd`, `swarm_drone_brain.gd`, `swarm_drone_config.gd/.tres`, `ENEMY.md`) | new enemy |
| Razor Drone | `assault/scenes/enemies/razor_drone/`: `git mv` of `drone_interceptor/`, classes renamed | evolved enemy |

Both enemies live under `assault/scenes/enemies/` even though they also fly in Open Space. This is because:
- `BaseEnemy` is still there until Ph15;
- five of the invariant gates discover the roster from that directory (`1-context.md` → *Gates*).

Nothing under `global/` references `ArenaCamera` or `BaseEnemy` (Phase 1 rule).

### 2.2 Steering additions (R2.2, R2.3, R2.7)

All are pure functions returning a desired velocity (or a scalar), unit-tested like Phase 1's nine primitives.

- `spiral(pos, center, radius, angle, radius_rate, max_correct_speed)`: an orbit whose radius the caller shrinks or
  grows each tick. It carries a drone from the wide REAR orbit in to the burst start point.
- `corkscrew(pos, forward_dir, speed, amplitude, phase)`: forward motion plus a perpendicular sinusoid (`phase` is
  advanced by the caller). It replaces the look of the legacy `sine()` rails on approach, so entries are not straight
  lines.
- `formation_slot(pos, vel, anchor, heading, slot_offset, speed, decel)`: `arrive` at
  `anchor + slot_offset.rotated(heading.angle())`. This is what the flank slots use.
- `separation(pos, neighbours, radius)`, `alignment(vel, neighbour_vels)`, `cohesion(pos, neighbours)`: the three
  flocking terms. Neighbours are **squad mates only** (O(k²), k ≤ 7; finding 1).
- `clamped_lead_time(distance, speed, t_min, t_max)`: `clamp(distance / speed, t_min, t_max)`, which gives the
  0.4–0.8 s ram prediction (finding 5). A zero or negative speed returns `t_min`.

**Composition rule (Phase 1 §2.4, unchanged):** a brain makes **one** primary request per state. The flocking terms
are summed, capped at `flock_nudge_cap × max_speed` (0.35 **[judgement]**) and offered through `mover.add_nudge()`.
There is no weighted blend of all terms: that was rejected in Phase 1.

### 2.3 `ContactProfile` (R2.14)

A `Node` child that owns what touching this enemy does. It mirrors `DefenseProfile` (the defensive side):
- `BaseEnemy._ready()` resolves the scene-authored `ContactProfile`, or creates a default.
- The default is `COLLISION`, which is exactly today's behaviour for every legacy enemy.

```
enum Mode { NONE, COLLISION, RAMMING, EXPLOSIVE }
@export var mode: Mode = COLLISION
@export var blast_radius: float = 0.0     # EXPLOSIVE only (px)
@export var blast_damage: int = 0         # EXPLOSIVE only
signal contact_made(area: Area2D)         # one emit per registered touch
signal detonated(position: Vector2)       # EXPLOSIVE only
func setup(hit_box: HitBox) -> void       # called by BaseEnemy with contact_hit_box (may be null)
func set_armed(armed: bool) -> void       # RAMMING / EXPLOSIVE only; no-op for NONE / COLLISION
func is_armed() -> bool
func detonate() -> void                   # EXPLOSIVE: one blast, idempotent
```

| Mode | `ContactHitBox` | On touch | Consumer |
|---|---|---|---|
| NONE | disabled (or absent) | nothing | Bonus Drone (already has no hitbox; the profile makes that explicit) |
| COLLISION | always on | `damage` from config, as today | every legacy enemy (default) |
| RAMMING | on **only while armed** | `damage` from config | Razor Drone (armed in DASH only) |
| EXPLOSIVE | on only while armed | `damage` from config, then `detonate()`, then the owner self-destructs | Swarm Drone (armed in BURST / second pass) |

The rules:
- **Damage stays `config.collision_damage`** on the `ContactHitBox` in every mode, so `test_enemy_contact_damage.gd`
  keeps its single rule. "Ramming: high damage only while committed" is expressed as *full damage while armed, none at
  rest*, with no second damage field.
- **Arming** toggles the hitbox's `monitorable` and `monitoring` with `set_deferred` (C5: toggling from inside a
  physics callback must be deferred). Whether a hitbox armed *while already overlapping* the player registers on the
  next physics step is engine behaviour. **It is pinned by a test, not assumed.**
- **Blast:** a child `HitBox` (circle `blast_radius`, layer `enemy_hitbox` 256, mask `player_hurtbox` 128,
  `damage_type = CONTACT`), created by the profile, disabled at rest. `detonate()` enables it for exactly **one physics
  frame** using an accumulated counter, never `create_timer` (brain rule and leak trap). It then emits `detonated`.
  The blast does **not** hit other enemies: enemy friendly fire is deferred (§8).
- **When EXPLOSIVE detonates:**
  - on a registered contact while armed;
  - when the owner dies **while armed**: shooting a committed drone point-blank sets off its blast. This is the
    blast's real gameplay value, because the player's 0.5 s i-frames (`PlayerBase.invincibility_sec`) swallow a blast
    that lands on the same frame as the contact.
  - Dying while unarmed never detonates.
  - To hook death, `ContactProfile` connects to the owner's `Health.amount_changed` itself (duck-typed through
    `setup()`'s owner), so `BaseEnemy`'s death hook is not changed.
- **Rails:** `BaseEnemy.suspend_ai()` calls `contact_profile.set_armed(true)`. A rail-driven Swarm Drone therefore
  hurts on contact exactly as the Kamikaze does today (C10). Legacy COLLISION is unaffected.
- **Contact death:** both new enemies connect `contact_made` to their own reaction:
  - Swarm → `health.set_health(0)`, so it is scored as a kill, which is Kamikaze parity.
  - Razor → none. It survives, and its brain reads `contact_made` to know the dash *hit*.
  - `DroneInterceptor._on_contact_hit` goes away with the rename.
- The profile never writes motion. `BaseEnemy` is an ancestor swept by the single-writer gate.

### 2.4 `SquadController` (R2.5, R2.15)

A `RefCounted` **role board** (research approach S-B). It moves nothing. Members read it and request their own motion,
so the single-writer gate holds. It is **event-driven, not clocked**: roles are recomputed only on join, leave or
`release_lead()`. This removes the frame-guard problem the research raised (a second clock, and manual `_tick()`s not
advancing `Engine.get_physics_frames()`).

```
enum Role { NONE, LEAD, FLANK_LEFT, FLANK_RIGHT, REAR }
enum Side { LEFT, RIGHT, FRONT, BACK }      # sectors relative to the player's heading
signal role_changed(member: Node, role: int)
func join(member: Node2D) -> void           # connects member.tree_exiting -> _on_leave
func role_of(member: Node) -> Role
func members() -> Array[Node2D]             # valid members only, join order
func rear_index(member: Node) -> int        # 0..n-1 among REAR members, for ring spacing
func claim_side(member: Node, preferred: Side) -> Side   # returns an unclaimed sector, latched until released
func release_side(member: Node) -> void
func release_lead(member: Node) -> void     # the lead finished its attack cycle: hand the token on
var attack_window_open: bool                # set by the LEAD entering BURST, cleared when its burst ends
var engaged: bool                           # latched by any member that perceives the player (hub idle)
var target_position_hint: Vector2           # updated by members from TargetInfo; used only to pick the next lead
```

**Assignment** (deterministic, testable without physics):
- 1 member: `LEAD`.
- 2 members: `LEAD` + `FLANK_LEFT`.
- 3 or more: `LEAD`, `FLANK_LEFT`, `FLANK_RIGHT`, and the rest `REAR`.
- **LEAD** goes to the valid member closest to `target_position_hint`, with ties broken by join order. This is DOOM's
  "closest steals the token" (finding 2).
- **Flanks** go to the next two closest. The one whose bearing (relative to the player's heading) is more to the left
  becomes `FLANK_LEFT`.

**Reassignment:**
- **The lead leaves** (dies, is freed, or is suspended by a rail and calls `leave()`): the board recomputes at once.
  Existing flanks keep their roles unless one of them becomes the new lead. In that case the closest REAR fills the
  vacated flank. This is "formation contracts" (IDEAS §17).
- **`release_lead()`:** the finishing lead drops to `REAR`, and the closest remaining member becomes `LEAD`.
- In Open Space this keeps the squad attacking in turns. In Assault each drone's `EngagementBudget` ends the rotation.

**Other rules:**
- **Membership is weak.** Members are checked with `is_instance_valid` and dropped on `tree_exiting`, and the board
  holds no strong reference to a `Node`.
- Members hold the only strong reference to the board, so when the last member is freed, the board is freed with it.
  No node, no clock, nothing to leak.
- **Side claims** implement "chooses a side of the player that is not already occupied" (R2.4). Each attacker claims
  one sector and keeps it (the side latch, finding 1) until its pass ends. If the preferred sector is taken, the nearest
  free sector is returned. If all four are taken, the preferred one is returned (shared).
- **`engaged`** is shared *state* on the board, not a message. Squad messaging (`TARGET_MARKED`, …) stays in Ph14.
  It exists so a hub squad engages together rather than one drone at a time.

**Where squads come from:**
- **Assault:**
  - `WaveBuilder.SpawnConfig.squad(id: StringName)` is a new fluent hint.
  - A `formation()` entry is **automatically** one squad.
  - Loose entries in one `b.wave()` that share a `squad()` id form one squad.
  - A loose entry with no id gets a squad of one.
  - `WaveManager._expand_formation()` and `_trigger_wave()` create **one `SquadController` per (wave index, squad key)**
    and store it in each expanded dict as `"squad"`.
  - `_spawn_ship()` sets `entity.set("squad", …)` before `add_child`, the same window `on_spawned` uses.
  - Entities without a `squad` property ignore it (duck-typed through `in`).
  - Members join in their own `_ready()`, so staggered `delay()`s are fine.
- **Open Space:** `SectorHub` builds one board and hands it to each Swarm Drone it spawns.
- `EnemyBrain` gains nothing. The Swarm brain reads `actor.squad`.

### 2.5 `AnchorIdle`: the generic idle → combat handover (R2.16, R2.17)

A `RefCounted` helper a brain owns. It is generic, for Ph14.

```
var anchor: Vector2
var perceive_radius: float     # enter combat inside this      (Razor 450 [judgement])
var lose_radius: float         # return to idle outside this   (Razor 700 [judgement]; must be > perceive_radius)
var notice_time: float         # the "noticed" beat before combat (0.35 s [judgement])
func update(delta, actor_pos, target: TargetInfo) -> int   # returns IDLE / NOTICING / COMBAT / RETURNING
```

- **Hysteresis:** COMBAT → RETURNING only beyond `lose_radius`, so there is no flicker at the boundary (finding 7).
  RETURNING → IDLE on reaching `anchor` within the idle ring. RETURNING → NOTICING again inside `perceive_radius`.
- **Cheap while idle:** idle ticks do a squared-distance check only. There is no prediction and no squad queries.
- **No snap:** the brain never sets a velocity on the transition. It changes which request it makes, and the mover's
  `acceleration` / `braking` blend it. The test states this as *per-tick velocity change ≤ acceleration·delta
  (+ ε)* across the handover.
- The irregular idle *motion* (drift, brake, reverse) belongs to the Razor brain (§2.8), not to `AnchorIdle`, which
  only decides *when*.
- **Assault skips idle:** a brain in a world with a provider (`EnemyWorld.arena(tree) != null`) starts in combat,
  because the level has already decided the fight is on.

### 2.6 `EngagementBudget` and the Assault exit (C1, C2, C3)

The corridor forces re-entry (Phase 1), so without an exit an AI drone lives until killed. The fix: **the brain
decides, the mover releases, the world rect frees.**

- `EngagementBudget` (`RefCounted`) has `seconds`, `update(delta) -> bool expired`, and `active`. `active` is
  `EnemyWorld.arena(tree) != null`, so the budget does nothing in Open Space.
- On expiry, the brain enters **DISENGAGE**:
  - it requests `retreat_from(player)`, biased to the nearer side or bottom edge;
  - it calls a new `EnemyMover.release_constraint()`, which sets `constraint = null` and records that it was released
    (a field on the mover, not a motion write, so it passes the single-writer gate);
  - it frees the actor once it is outside `EnemyWorld.projectile_world_rect()` (strict `<`/`>` compare, as in
    `_check_dash_end()`).
- **Scoring** is unchanged: a drone that leaves has `was_killed == false`, so `ScoreTracker` counts it as escaped, the
  same as a Kamikaze leaving the bottom edge today.
- `MovementConstraint.inner_rect() -> Rect2` is new. The identity returns an empty rect, meaning "unbounded". The
  corridor returns its `visible` rect. Brains use it to keep an orbit *centre* inside the corridor (R2.13) without
  naming `ArenaCamera`.
- **Budget values:**
  - They are **derived**, not tuned. The legacy rail drone is visible for about 3.4–3.6 s (research §3.6). Adding one
    ram cycle (wind-up 0.4 + burst 0.45 + overshoot ≈ 1.2) gives **Swarm 6.0 s**.
  - The Razor legacy has no lifetime; its lifetime was "until the dash leaves". Its budget is one full combat cycle
    plus a second: **Razor 9.0 s [judgement]**.
  - Both live in the configs (`engage_seconds`).
  - A test pins `swarm engage_seconds + worst exit time < LevelDirector's enemies_cleared_timeout (10 s)`, so
    cloud_descent's ENEMIES_CLEARED wait is not stretched (C2). The exit time is the worst-case distance to the world
    rect ÷ `exit_speed`.

### 2.7 Swarm Drone (R2.1–R2.7, R2.18)

- **Scene:** `swarm_drone.tscn`, root `SwarmDrone extends BaseEnemy` with these children:
  - `Health`, `HurtBox`, `HitFlashAnimationPlayer`, `ContactHitBox`;
  - `ContactProfile` (EXPLOSIVE);
  - `Brain` (`SwarmDroneBrain`), `EnemyMover` (`AUTO`);
  - `StateLight`, `Sprite2D`.
- **Art and collision:** the art is the Kamikaze's `drones.png` cell until task `t12-art-swarm` replaces it. The
  collision circle is sized to a 32 px hull (r ≈ 13). The hurtbox and contact box share the body shape id and scale
  (gates).
- **Config:** `SwarmDroneConfig extends ShipConfig`, flat `@export_group`s:

  | Field | Value | Source |
  |---|---|---|
  | `max_health` | 30 | Kamikaze parity |
  | `collision_damage` | 30 | Kamikaze parity (now actually applied, S10) |
  | `score_value` | 10 | Kamikaze parity |
  | Movement: `max_speed` 220, `acceleration` 600, `braking` 500, `max_turn_rate` 5.0 | | [judgement] |
  | Tactics: `rear_orbit_radius` 260, `rear_orbit_speed` 1.4 rad/s | | [judgement]: wide orbit |
  | Tactics: `flank_distance` 200, `flank_angle_deg` 70 | | [judgement] |
  | Tactics: `separation_radius` 30, `flock_nudge_cap` 0.35 | | finding 1 + [judgement] |
  | Attack: `windup_seconds` 0.4 | | finding 3 (≥ 0.34 s floor) |
  | Attack: `burst_speed` 480, `burst_seconds` 0.45 | | Interceptor dash speed; [judgement] |
  | Attack: `lead_time_min` 0.4, `lead_time_max` 0.8 | | IDEAS §5.1 |
  | Attack: `overshoot_seconds` 0.6, `second_passes` 1 | | IDEAS §5.1; [judgement] |
  | Attack: `blast_radius` 48, `blast_damage` 15 | | [judgement] |
  | Tactics: `engage_seconds` 6.0, `exit_speed` 260 | | §2.6 |

  The brain copies the config values in `_ready()`, as the Interceptor did. The config holds no nested resources.
- **Brain states:** `APPROACH → FORM → WINDUP → BURST → OVERSHOOT → (WINDUP → BURST → OVERSHOOT)×second_passes →
  REJOIN → FORM …`, plus `IDLE`/`NOTICING` (Open Space hub only, via `AnchorIdle` around the squad anchor) and
  `DISENGAGE` (Assault only).
  - **APPROACH:** `corkscrew` toward the player until inside `rear_orbit_radius + 100`. Each drone's corkscrew phase is
    drawn from `rng` (R2.3).
  - **FORM** (by role):
    - REAR: `orbit` at `rear_orbit_radius`, angle = `phase_offset + rear_index × TAU / rear_count`, where
      `phase_offset` is from `rng`.
    - FLANK_*: `formation_slot` at `flank_distance`, at ±`flank_angle_deg` off the player's heading. The heading is the
      velocity, or `facing` when the player is nearly still (below 20 px/s).
    - LEAD: `spiral` inward from its current radius toward `flank_distance`, then WINDUP.
    - Every role adds the flocking nudge. "Player avoidance until commitment" is an `evade` nudge within 90 px, applied
      only outside WINDUP/BURST.
  - **Who attacks:**
    - The LEAD attacks on its own.
    - FLANKs start WINDUP when `squad.attack_window_open` becomes true, which gives the pincer.
    - REAR never attacks.
    - A squad of one is its own LEAD.
  - **WINDUP** (yellow light, `windup_seconds`):
    1. Claim a side (`claim_side`, preferring the sector the drone is already in).
    2. Lock `lead = clamped_lead_time(dist, burst_speed, 0.4, 0.8)`.
    3. Lock `aim = predicted_position(lead)`.
    4. Offset `aim` laterally by one hull width toward the claimed side, so two attackers do not converge on one point.
    5. Hold position and face `aim` (`hold_position` + `face_toward`).
  - **BURST** (red light, profile armed): `mover.boost(dir_to_aim, burst_speed, burst_seconds)`. The LEAD sets
    `squad.attack_window_open = true` on entry. Touching the player → the EXPLOSIVE profile detonates → self-destruct.
  - **OVERSHOOT** (light off, profile disarmed): the burst ended without contact, which is a *miss*. Keep requesting
    the burst direction at `max_speed` while `max_turn_rate` bends the heading back toward the player for
    `overshoot_seconds`. This is the "curves away" arc. Release the side claim.
  - **Second pass:** if `passes_left > 0`, go back to WINDUP. Otherwise REJOIN: the LEAD calls `release_lead()`, and
    every attacker returns to FORM in its (possibly new) role.
  - **No player** (`has_target == false`): FORM around the last known position, or around the squad anchor in the hub.
- **Assault adaptation (R2.6):** the same brain, with an `AUTO` mover (corridor). There is no idle, and the
  `EngagementBudget` is active. The corridor's per-axis filter is what turns the orbits into "partial circles inside
  the lane". Brains clamp orbit centres to `inner_rect()` shrunk by the orbit radius, so an orbit near an edge does not
  fight the pressure. Spawns above, below or at the side of the screen enter through the corridor's not-entered rule
  (Phase 1).
- **Rails:** when suspended (station BOTTOM squad), the profile is armed permanently, the brain is inert, and the drone
  leaves its squad.

### 2.8 Razor Drone (R2.8–R2.13, R2.16)

**Step A (rename, no behaviour change):**
- `git mv assault/scenes/enemies/drone_interceptor assault/scenes/enemies/razor_drone`.
- Files renamed to `razor_drone.*`, `razor_drone_brain.gd`, `razor_drone_config.*`. `.uid` sidecars travel with them
  (never hand-type a UID).
- Classes renamed to `RazorDrone`, `RazorDroneBrain`, `RazorDroneConfig`.
- `WaveBuilder.DRONE_INTERCEPTOR`/`drone_interceptor()` renamed to `RAZOR_DRONE`/`razor_drone()`.
- The rosters, `test_drone_interceptor.gd` → `test_razor_drone.gd`, `test_enemy_dual_mode.gd`, and the station guard's
  constant follow.
- Every existing pin stays green **unchanged in substance**.

**Step B (combat):** evolve `RazorDroneBrain` to
`ENTER → ORBIT ⇄ REVERSE → (FEINT | WINDUP) → DASH → OVERSHOOT → RETURN → ORBIT`, with DISENGAGE in Assault.

- **Mover:** `acceleration` 900, `braking` 700, `max_turn_rate` 6.0 rad/s, `constraint_mode = AUTO`. The zeroes go
  away; this is the re-pin D5 names. **[judgement]**
- **ORBIT:** as today (`orbit_radius` 130, `orbit_speed` 1.8), plus an `orbit_dir` of ±1.
  - Each orbit window (the rng-drawn 1–2 s timer, as today) ends in a roll.
  - With `reverse_chance` (0.35 **[judgement]**, finding 6) the drone goes to **REVERSE**. REVERSE ramps its angular
    speed from `orbit_dir × orbit_speed` through 0 to `-orbit_dir × orbit_speed` over `reverse_seconds` (0.25), which
    is a visible brake. It then starts a new orbit window. A reversal can happen at most once per window.
  - Otherwise it rolls fake versus real: `fake_chance` 0.35 **[judgement]**.
- **FEINT** (fake dash):
  - The yellow light is on for `windup_seconds × fake_windup_scale` (0.5 × 1.5 = 0.75 s), facing the player (finding
    4: a feint is a longer telegraph).
  - It then requests a short lunge at `dash_speed × 0.5` along the facing and immediately brakes (`braking`), so it
    "slides past".
  - It then re-orbits with `_orbit_angle += PI` and `orbit_dir` flipped: it attacks from the opposite side, going
    straight into WINDUP without another roll.
  - **The profile is never armed and the white light is never shown.** At most one feint per cycle.
- **WINDUP** (real): yellow for `windup_seconds` (0.5, finding 3), then white commit flash for `commit_flash_seconds`
  (0.12). The white is exclusive to the real dash (R2.11, finding 4). The direction is locked at the start of the
  commit flash: `predicted_position(dash_prediction_time)` (0.2 s, as today).
- **DASH:** the profile is armed (RAMMING). `boost(dir, dash_speed, dash_seconds)`, where
  `dash_seconds = min((dist_to_locked_point + overshoot_px) / dash_speed, 0.9)` and `overshoot_px` is 120.
  `contact_made` during the boost marks the dash as a **hit**.
- **OVERSHOOT:** disarm. The mover's `braking` and `max_turn_rate` bring it round. If the dash was *not* a hit, fire
  the pulse **exactly once**:
  - `AttackController` (`driven_by_brain = true`, `enabled = false` between pulses) with `fire_now()`;
  - `AimedAttackPattern` (damage 10, speed 250, accuracy 0);
  - its own `BulletPool` (pool_size 4) → `EnemyBullet`.
  - This is the first real consumer of `fire_now()` (Phase 1 gap). "Missed" is defined as *the boost ended with no
    `contact_made`*, not as a distance.
- **RETURN:** `arrive` back to orbit radius, then ORBIT with a fresh window.
- **Assault adaptation (R2.13):** the orbit centre is the player clamped into `inner_rect()` shrunk by `orbit_radius`.
  A dash only commits when the drone's bearing from the player is within a **side lane**: 30°–75° off the vertical
  axis, on either side **[judgement]**. When the roll fires outside the lane, ORBIT continues until the drone is in a
  lane (bounded by one extra orbit window, then it commits anyway). This gives "attacks diagonally from a side lane".
  In Assault the `EngagementBudget` (9 s) then triggers DISENGAGE.
- **Open Space:** the dash no longer frees the drone. `dash_max_distance` is **removed** from config, script and test,
  because nothing reads it once the Razor survives its dash.
- **Idle (§18.5, R2.16), Open Space only:**
  - `AnchorIdle` runs around a patrol anchor.
  - IDLE_ORBIT uses a slow orbit (`idle_radius` 160 ± 40 from `rng`, `idle_speed` 0.5 ± 0.2 rad/s, where the radius
    and speed are re-drawn each leg).
  - Each leg lasts 2–4 s and ends in one of IDLE_BRAKE (0.6 s hold), IDLE_REVERSE (flip `orbit_dir`), or a short
    `boost` at 1.8 × idle speed. Each is equally likely, drawn from `rng`.
  - On COMBAT, it goes to NOTICING (yellow light blinks once, faces the player for `notice_time`), then ENTER **from
    its current velocity**. On RETURNING, it `arrive`s to the anchor and resumes IDLE_ORBIT.
- **Config additions** (flat): `reverse_chance`, `reverse_seconds`, `fake_chance`, `fake_windup_scale`,
  `windup_seconds`, `commit_flash_seconds`, `overshoot_px`, `max_dash_seconds`, `pulse_damage`, `pulse_speed`,
  `engage_seconds`, `exit_speed`, `side_lane_min_deg`, `side_lane_max_deg`, `idle_radius`, `idle_radius_jitter`,
  `idle_speed`, `idle_speed_jitter`, `perceive_radius`, `lose_radius`, `notice_time`.
- **Test seams:** `force_next_choice(&"real" | &"fake" | &"reverse")`, alongside the existing `_begin_dash()` seam.
  Tests never depend on a seed's luck for which branch runs.

### 2.9 Readability and sprites (R2.19)

- **`StateLight`** (`global/components/state_light.gd`, `Node2D` with one small `Sprite2D`):
  `set_state(OFF | ARMED | CHARGING | COMMIT)`, which maps to off / red / yellow / white.
  - Only the light is recoloured. The hull keeps the faction palette (IDEAS §21.1).
  - Its brightness is capped below `EnemyBullet`'s (finding 9: projectiles must stay the most vivid thing on screen).
  - It is placed at the sprite's "eye". Brains call it duck-typed through `actor.get_node_or_null("StateLight")`.
  - Its state is readable, so the tests can assert the telegraph ("the fake never shows COMMIT").
- **Sprites:** two generations under the `pixel-art-generation` skill (strict top-down, `view: "high top-down"`,
  `isometric: false`), saved with `scripts/pixellab.sh`, each opened and checked by eye.
  - Swarm: **32×32**, exaggerated silhouette (e.g. a four-prong "caltrop"), dark hull, cool blue edge highlight, red or
    maroon faction stripe, a clear eye socket for the light.
  - Razor: **48×48**, blade or crescent silhouette that is clearly *not* the Swarm's, the same palette rules.
  - Nose-up art sets `sprite_forward_angle = -PI/2`. Both must pass `test_entity_sprite_transparency.gd` (use
    `scripts/strip-sprite-bg.sh`, never a regeneration, to fix a background).
  - One attempt plus one fix pass each (C11). Audio cues are out of scope (§8).

### 2.10 Assault level 1 (R2.23, R2.18)

Two steps, so the risky one is isolated:

1. **Swap under rails.**
   - `WaveBuilder.DRONE` points at `swarm_drone.tscn`. Every existing `.move()` drone line, including the station's
     BOTTOM squad, now spawns a rail-driven Swarm Drone: armed profile, the same straight or sine path, the same
     cull.
   - Delete `kamikaze_drone/`. The level still plays as before, with new art and an explosion on contact.
   - The Bonus Drone is untouched (it has its own `BONUS_DRONE` constant and `_spawn_bonus_drone`).
2. **Rails off.**
   - Remove `.move(...)` from **every** `b.drone()` line in `level_1_director.gd` (119 lines, research count, re-counted
     by the t1 pin) and from the two Razor lines (which already have none).
   - Keep `.at()`, `.formation()` and `.delay()` exactly. A `.free_after()` on a line that loses `.move()` is dropped
     too, since only a path mover reads it; the `EngagementBudget` replaces it.
   - Group into squads: formations automatically; loose drone lines in one wave share `squad(&"w<n>")` when the wave
     has 2–7 drones. The 7-drone wave is the largest, so squads stay within IDEAS' "3–6 + one".
   - The station BOTTOM squad **stays on rails**: the station is not in scope, and its tests pin a straight 170 px/s
     path.
   - The t1 characterization pin is updated to assert: triggers, offsets, delays and formation shapes are equal to the
     pinned list, and `movement == null` for every drone and razor spawn.

`SineMovement` and friends stay: other enemies still use them until Ph15.

### 2.11 Open Space hub (R2.22, R2.1)

- `SectorHub` loses `PATROL_DRONE`, `drone_count` and `_spawn_initial_drones()`. It gains `_spawn_patrol()`:
  - `@export var patrol_seed: int = 0` (0 = randomize) → a local `RandomNumberGenerator`;
  - `@export var squad_size: int = 4`, `patrol_ring_radius: float = 900.0`.
- It spawns one Swarm squad (`squad_size` drones, one shared `SquadController`, local anchor on the ring at a seeded
  angle) and one Razor Drone (its own anchor on the ring at +120° to +240° from the squad).
- The anchor is the hub origin, the same as today (H1 in research §3.8). Each group idles around its own point on the
  ring.
- Geometry guarantees no perception at spawn: `900 − idle_radius_max (200) = 700 > perceive_radius (450)`. A test pins
  it on the real `sector_hub.tscn` (C4).
- The Swarm's hub idle is a loose REAR-style orbit around its anchor through `AnchorIdle`. Any member perceiving sets
  `squad.engaged`, and the whole squad transitions.
- Delete `open_space/scenes/entities/enemies/patrol_drone.{gd,tscn}` and `tests/integration/test_patrol_drone.gd`.
  Update `Steering.drift`'s comment.
- The hub tests that add `sector_hub.tscn` to the tree must stay green unchanged.
- Enemy bullets (the Razor's pulse) land in `EnemyContainer` through the existing grandparent rule (D4, pinned).

---

## 3. Build sequence

Each step is one task in `tasks.json` (same key).

1. **`t1-pin-drone-spawns`** (test): characterization before anything moves.
   - Pin level 1's drone and interceptor spawn list: trigger, offset, delay, formation type and size, and `movement`
     non-null for drones. Build it from `_build_sections()` data, not text.
   - Pin the station BOTTOM squad and the hub's current spawn (count 3, radius band 300–600).
   - Add **completeness guards** to `test_enemy_contact_damage.gd` and `test_contact_hitbox_geometry.gd`: every
     `<dir>/<dir>.tscn` BaseEnemy root in `assault/scenes/enemies` must be in the roster.
   - Record level 1's peak concurrent drone count under legacy lifetimes, computed from the pinned list, in the test
     header as a number.
2. **`t2-steering`**: §2.2 primitives and unit tests.
3. **`t3-contact-profile`**: §2.3. `BaseEnemy` resolves or creates it, `suspend_ai()` arms it, legacy is COLLISION.
   `test_contact_profile.gd`, including the engine overlap-at-arm pin. Every legacy pin stays green.
4. **`t4-squad-controller`**: §2.4 board and unit tests over fixture nodes.
5. **`t5-wave-squads`**: `WaveBuilder.squad()`, formation → squad, and `WaveManager` threading, with tests using a
   fixture scene that has a `squad` property.
6. **`t6-engagement-exit`**: `EngagementBudget`, `EnemyMover.release_constraint()`, `MovementConstraint.inner_rect()`
   and the corridor override, with the §2.6 derived-budget test.
7. **`t7-anchor-idle`**: §2.5 helper and unit tests.
8. **`t8-swarm-drone`**: §2.7 scene, brain, config, `StateLight` and gate rosters, with the dual-mode spec.
9. **`t9-razor-rename`**: §2.8 step A.
10. **`t10-razor-combat`**: §2.8 step B (without idle), with the re-pins and the dual-mode spec.
11. **`t11-razor-idle`**: §2.8 idle, on `AnchorIdle`.
12. **`t12-art-swarm`**, **`t13-art-razor`**: the sprites.
13. **`t14-swap-kamikaze`**: §2.10 step 1, and delete `kamikaze_drone/`.
14. **`t15-level1-ai`**: §2.10 step 2.
15. **`t16-hub-patrol`**: §2.11, and delete PatrolDrone.
16. **`t17-docs`**: `updating-project-docs`, the per-enemy `ENEMY.md` files, `docs/enemy-roster.md`, the CLAUDE.md gate
    list, DECISIONS *as built*, and the dossier.

Parallelism: t1, t2, t4, t6 and t7 are independent. t8 needs 2, 3, 4 and 6. The Razor chain (9 → 10 → 11) waits on t8
because both edit the same gate rosters and t8 creates `StateLight`. t14 waits on t9 for the same reason: both rewrite
the rosters, the t1 pin and `test_station_reinforcements.gd`. t13 waits on t11 because both touch the Razor scene.

---

## 4. Test plan

Parameterized dual-mode tests use `use_parameters(["open_space", "assault"])` on a **string label**, and build the
harness inside the body (DECISIONS t12 leak trap). Mover-owned bodies are driven with `_tick()`. Every test sets
`rng_seed` or uses the `force_next_choice` seam. Run `scripts/check-test-leaks.sh` after every task that adds such
tests.

| File | Cases (boundary cases in **bold**) |
|---|---|
| `tests/integration/test_level1_drone_spawns.gd` (t1, updated in t14/t15) | Pinned spawn list equals the live one. After t15: `movement == null` for every drone and razor; triggers, offsets and delays unchanged. **A drone line re-given `.move()` fails** |
| `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd` (t1) | Completeness guard. **Temporarily removing a roster entry fails** (verified once by hand) |
| `tests/unit/test_steering.gd` (t2, extended) | spiral holds radius when `radius_rate = 0` and shrinks when negative; corkscrew's mean heading = forward over one period; formation_slot arrives and stops (**zero offset = arrive at anchor**); separation **zero with no neighbours** and **finite with a coincident neighbour**; alignment = mean velocity; cohesion toward the centroid; clamped_lead_time **clamps at both ends** and **speed 0 → t_min** |
| `tests/unit/test_contact_profile.gd` (t3) | Mode matrix; COLLISION always monitorable; RAMMING off at rest and on after `set_armed(true)` + one physics frame; EXPLOSIVE detonates on contact while armed; **death while armed detonates, death unarmed does not**; blast active for **exactly one physics frame**; `detonate()` idempotent; `suspend_ai()` arms; **arming while already overlapping a player hurtbox registers exactly one hit** (engine pin, C5) |
| `test_base_enemy.gd` (t3, extended) | Every legacy roster enemy resolves a COLLISION profile; the Bonus Drone resolves NONE or has no hitbox; the hurtbox masks are unchanged |
| `tests/unit/test_squad_controller.gd` (t4) | Roles for 1/2/3/6/**7**; the lead is closest to the hint; **the lead freed → the closest remaining becomes lead in the same call**; a flank promoted to lead → a REAR fills the flank; `release_lead` rotates; `claim_side` returns a free sector, **all four taken → the preferred one**; **the last member freed → no valid members, and the board is released** (weakref null); `role_changed` arity |
| `tests/integration/test_wave_squads.gd` (t5) | A formation of 4 → one board shared by 4; two loose entries with the same `squad()` id → one board; no id → a board of one each; **the same id in two different waves → two boards**; an entity without a `squad` property spawns without error |
| `tests/unit/test_engagement_budget.gd` + `test_enemy_mover.gd` + `test_assault_corridor_constraint.gd` (t6) | Budget inactive without a provider; expires at `seconds`; `release_constraint()` → outward velocity passes unfiltered; `inner_rect()` is empty for the identity and equals the visible rect for the corridor; **derived: swarm `engage_seconds` + worst exit < 10 s** |
| `tests/unit/test_anchor_idle.gd` (t7) | IDLE → NOTICING at `perceive_radius`; NOTICING → COMBAT after `notice_time`; **no flip between perceive and lose radius** (oscillate at 500 px for 5 s); RETURNING → IDLE at the anchor; **perceive ≥ lose rejected** (push_error and clamp) |
| `tests/integration/test_swarm_drone.gd` (t8) | Dual-mode: REAR holds `rear_orbit_radius` ± 10 %; the ram aim equals `predicted_position(t)` with t ∈ [0.4, 0.8] (**far target → 0.8, near → 0.4**); a burst toward a stationary player uses `facing` for sides; **two attackers never claim the same side**; a miss → OVERSHOOT → exactly one more pass → REJOIN (the lead has released); contact while armed → detonates and frees and scores as a kill; **no contact damage while in FORM** (touching the player unarmed deals 0); role reassignment after the lead is freed mid-burst; formation recovery (displace every member 150 px, all are back within tolerance of slot or ring within 3 s); phase offsets: 5 drones from identical spawns hold pairwise-distinct positions after 2 s. Assault only: the budget → DISENGAGE → freed outside the world rect, **never before `engage_seconds`**; a below-screen spawn enters; a burst toward an edge stays inside the hard band. Rail: an `EnemyPathMover` suspends → armed, leaves its squad |
| `tests/integration/test_razor_drone.gd` (t9 rename, t10/t11 extend) | t9: every old pin green under the new names. t10 (dual-mode): orbit radius; **reversal changes the sign of angular velocity through zero, never instantly**; the fake shows CHARGING for 1.5× the windup, never COMMIT, never arms; **the fake ends on the opposite side** (bearing differs by > 120°); the real dash shows CHARGING → COMMIT → armed; dash direction = locked prediction; a missed dash → **exactly one** pulse bullet acquired from the pool; **a hit dash → zero pulses**; it survives the dash (not freed); Assault: the dash bearing is in the side lane, the orbit centre is inside the inner rect, the budget exit. t11 (Open Space): idle stays within the anchor ring; brake/reverse/boost all occur over a seeded 30 s; **the handover velocity change per tick ≤ acceleration·delta + ε**; hysteresis; returns to idle beyond `lose_radius` |
| `test_enemy_dual_mode.gd` (t9/t10) | Interceptor cases renamed, then rewritten as Razor cases: "identical in both modes" becomes "identical relative to the constraint" |
| `test_station_reinforcements.gd` (t14) | BOTTOM squad = 2 × `swarm_drone.tscn` on rails, the same path; **a rail swarm drone touching the player deals `collision_damage`** |
| `tests/integration/test_sector_hub_patrol.gd` (t16) | One squad of `squad_size` Swarm Drones + one Razor; seeded positions are reproducible; **nobody perceives the player at frame 0**; no `PatrolDrone` reference in `res://` (text sweep); a Razor pulse bullet's parent is `EnemyContainer` (D4) |
| Existing gates (all tasks) | `test_enemy_hurtbox_geometry`, `test_config_instance_isolation` (floor 10 still holds: −kamikaze +swarm, a rename is net 0), `test_entity_sprite_transparency` (floor 12), `test_enemy_mover_single_writer` (both brains and the squad), `test_signal_emit_arity` (`contact_made`, `detonated`, `role_changed`), `test_project_load_integrity`, `test_resource_uid_integrity`, the Bonus Drone pins **unchanged** (R2.18) |

What the gate **cannot** show: whether the swarm is fun, whether level 1's density feels right, and whether the lights
read at speed. t15 and t16 end with a written hand-playtest checklist in their final message. The dossier lists these as
known gaps.

---

## 5. Risks

| Id | Risk | Mitigation |
|---|---|---|
| C1/C2 | AI drones never leave the corridor, or stall sections | §2.6 budget + release + world-rect free; the derived < 10 s test |
| C3 | Level-1 difficulty spike (drones live about 6 s instead of about 3.5 s) | Squads cap attackers at 3 per squad (lead + flanks). t1 records the legacy peak concurrency, and t15 records the new one computed with 6 s + exit. **If the new peak is more than 2× the legacy one, t15 stops and escalates** rather than tuning blind |
| C4 | Hub ambush at spawn | §2.11 geometry + test |
| C5 | Area arm and disarm timing | Pinned engine behaviour (t3); `set_deferred` everywhere |
| C6 | Squad dangling references | Weak membership, `tree_exiting`, RefCounted lifetime (t4 tests) |
| C7 | Nondeterminism | `brain.rng`, `patrol_seed`, `force_next_choice` seams |
| C8 | Deleting scenes breaks load/UID gates or docs | Completeness guards first (t1); `git mv` for the rename; deletions in their own tasks (t14, t16) |
| C9 | The corridor has never been played with real AI | The Razor re-pins the edge behaviour; band values unchanged unless a test shows why |
| C10 | Rail Swarm must still hurt | `suspend_ai()` arms (t3), tested on the real station spawn (t14) |
| C11 | Art budget | Two generations + fix pass; state via `StateLight`, not extra frames |
| C12 | The explosive blast near the player feels unfair | The blast only fires when armed (red light), radius 48 is under 2 hull widths, damage 15 is half the contact damage. Tunable in `.tres` |
| C13 | The rename touches many files in one commit | Its own task (t9) with no behaviour change, so a failure is attributable |

---

## 6. Requirements coverage

| Req | What | Task(s) |
|---|---|---|
| R2.1 | Swarm replaces Kamikaze and PatrolDrone, 24–36 px | t8, t12, t14, t16 |
| R2.2 | Lightweight flocking + player avoidance + lateral offset | t2, t8 |
| R2.3 | Per-drone phase offsets | t8 (rng phase + rear spacing; tested) |
| R2.4 | Coordinated ram: orbit → 0.4–0.8 s prediction → free side → burst → overshoot → one second pass | t2, t4, t8 |
| R2.5 | Lead / flanks / rear, reassignment on lead death | t4, t8 |
| R2.6 | Swarm in the Assault corridor | t6, t8, t15 |
| R2.7 | spiral / corkscrew | t2 |
| R2.8 | Razor evolves the Interceptor, 40–56 px, full state chain | t9, t10, t13 |
| R2.9 | Orbit reversal | t10 |
| R2.10 | Fake dash, attack from the opposite side | t10 |
| R2.11 | The real dash's cue is stronger than the fake's | t8 (`StateLight`), t10. **Audio: out of scope** (no SFX pipeline for enemies; §8) |
| R2.12 | Contact damage + pulse after a missed dash | t3, t10 |
| R2.13 | Razor in Assault: orbit band, side-lane diagonal attack | t6 (`inner_rect`), t10 |
| R2.14 | Contact profiles None / Collision / Ramming / Explosive | t3 (Armour collision → Ph4) |
| R2.15 | SquadController with roles; formations only as spawn layouts | t4, t5, t15 |
| R2.16 | Razor idle + generic handover | t7, t11 |
| R2.17 | Idle cheaper than combat | t7 (squared-distance only while idle; tested by construction: no TargetInfo prediction calls) |
| R2.18 | Retire Kamikaze and PatrolDrone, keep the Bonus Drone | t14, t16; the Bonus Drone pins stay unchanged in every task |
| R2.19 | Readability: silhouette, faction accents, one light per state | t8 (`StateLight`), t12, t13 |
| R2.20 | Deterministic dual-mode tests over the listed behaviours | t8, t10, t11 (§4) |
| R2.21 | §41 Phase 2 items 1–2 | the whole epic. Items 3–4 (Fighter, Gatling) → **Phase 3** |
| R2.22 | Hub ambient spawn → Swarm squad + Razor | t16 |
| R2.23 | Level-1 migration, layouts and timing preserved | t1, t14, t15 |
| R2.24 | Gates cover the new scenes | t1 (guards), t8, t9, t10, t14 (rosters) |
| §3.2 other primitives (regroup, break_contact, lead_target) | | later phases 3, 4, 14 (DECISIONS) |
| §16 Armour collision | | **Phase 4** (Ram Corvette) |
| §17/§35 for non-drone enemies, §18 messages | | **Phase 14** (squads for fighters in Phase 3 reuse `SquadController`) |
| §18.5 idle for other families | | **Phase 14** |
| §2/§38 Salvage Drone Open Space event | | **Phase 13** (EncounterDirector) |
| §21–23 for other enemies, audit | | **Phase 17** |
| §32 EncounterDirector, §33 leash / search | | **Phase 13** (only the idle `lose_radius` return exists here) |
| Other level-1 enemies off rails | | **Phase 15** |
| Enemy friendly fire from blasts | | out of scope: no design decision exists; `blast_mask` is fixed at 128 |
| Audio telegraphs | | out of scope: the project has no enemy SFX; Ph17's readability pass can add them |

---

## 7. Out of scope

- The EncounterDirector, leash and search behaviour, respawning hub patrols (Ph13).
- Squad messages (Ph14).
- Fighter and Gatling (Ph3).
- The Armour contact profile (Ph4).
- Hazard avoidance (Ph6).
- Difficulty tiers (Ph16).
- Enemy audio.
- Changing the station boss beyond pointing its two BOTTOM drones at the new scene.
- `BulletPool` container injection (D4).
- Moving `BaseEnemy` to `global/` (Ph15).
- Retiring `SineMovement` and the other path resources (Ph15).

## 8. Open questions for the owner (not blocking)

1. **Explosive blast vs the player's own shots:** the plan makes an armed Swarm Drone detonate when shot. If that feels
   unfair in play, set `blast_damage = 0` in the `.tres` (the contact damage still applies).
2. **Hub anchor:** H1 keeps the hub origin as the anchor, with patrols on a 900 px ring. If they get in the way of the
   mission planets (650–740 px), moving the ring is a config change (`patrol_ring_radius`).
3. **Assault squads for loose drone lines** are grouped by wave. If a specific wave should behave as independent
   drones, drop its `squad()` hint.
