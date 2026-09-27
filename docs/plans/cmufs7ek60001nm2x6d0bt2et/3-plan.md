# Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles — plan

Epic `cmufs7ek60001nm2x6d0bt2et`, plan task `cmufs7ekl0009nm2x5rh6gubn`, 2026-09-27. **Revision 2.** It answers
review round 1 (`4-review.md`: B1–B4, N1–N12). §9 maps each finding to what changed.

Built on `1-context.md` (code facts, requirement ids `R2.1`–`R2.24`, gate table) and `2-research.md` (scope check
`S1`–`S11`, findings 1–9, risks `C1`–`C11`), both beside this file. It is not re-derived here. It also builds on the
idea's decision log `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (Phase 1 plan and *as built*) and on
`docs/epics-done/cmufklb100001p92xs1ey2fb1/REPORT.md`. Where this plan changes a Phase 1 decision, §2.0 says so.

Values marked **[judgement]** have no citable source. They are starting defaults, set in `.tres` configs so they can be
tuned without code changes. Values marked **[computed]** were computed for this revision by a throw-away headless
script over `Level1Director._build_sections()` (script in `/tmp`, nothing committed). The t1 and t15 tests recompute
them from the same data. Symbols are cited instead of line numbers because line numbers drift.

**Correction to `1-context.md`:** it says 13 drone formations in level 1. There are **14** (cluster ×7, wedge ×6,
line ×1). The t1 pin counts them from data, so no number is hand-copied into a test.

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
  *going* (a red light while it is dangerous). If it misses, it overshoots, **curves** round and tries once more. When
  the lead dies, another drone takes its place.
- The **Razor Drone** (48 px) is what the Drone Interceptor becomes. It circles you, sometimes reverses direction, and
  sometimes fakes a dash: it winds up, lunges past you, brakes and attacks from the other side. Only the real dash
  shows the white "commit" flash. It survives a miss, fires one pulse shot at you, and curves back round.
- Touching a drone only hurts **while it is attacking** (its red light is on). A Swarm Drone that hits you explodes.
  Shooting one point-blank while it is armed sets off its blast, and the blast hurts you if you are close.
- In **Open Space** the hub has a Swarm squad (below the hub) and a Razor Drone (above it) idling on patrol, out of
  reach of where you spawn, the planets and the pickups. Fly close and they notice you, turn and fight — the whole
  squad at once.
- In **Assault level 1**, the drones arrive at the same moments and places as before. They then fight inside the
  corridor instead of flying a rail, and leave after a short engagement so the level's pacing holds.
- The **Bonus Drone** does not change.

---

## 2. Design

### 2.0 Changes to earlier decisions, stated explicitly

| # | Phase 1 decision (DECISIONS.md) | Change | Why |
|---|---|---|---|
| D1 | L11 roadmap: Explosive collision in Ph7 | Built **here**, used by the Swarm Drone | Phase scope names it (research S1). Ph7 reuses it |
| D2 | §18.5 idle profiles → Ph14 | The **generic** anchor-idle → combat handover (`AnchorIdle`), the Razor idle and the Swarm squad's hub idle are built here. Other families' idle profiles stay in Ph14 | Phase scope (S2). The Swarm idle is needed because the hub spawns a Swarm squad (R2.22). Ph14 builds on this contract |
| D3 | Assault migration → Ph15 | Only level-1 Kamikaze/Interceptor spawns and the station's two BOTTOM drones move now. Everything else stays on rails until Ph15 | Phase scope (S3) |
| D4 | P-18: make `BulletPool`'s grandparent container injectable in Ph2 | **Not done.** A test pins that the Razor's pulse lands in the hub's `EnemyContainer` | Every real parent chain already satisfies pool → ship → container (S7). Churning seven pool users buys nothing yet. It stays open for Ph5 (owner-bound projectiles) |
| D5 | Interceptor pins "1:1 with pre-port" | Retired and rewritten as Razor pins. The corridor is turned **on** (`constraint_mode = AUTO`) | DECISIONS already said Ph2 re-pins (S9) |
| D6 | Legacy dash cull via `EnemyWorld.cull_rect()` | Assault AI drones exit through **`EnemyWorld.projectile_world_rect()`** (it covers every camera pan) after a released constraint. `cull_rect()` stays for legacy users | The cull rect is fixed to the camera's pinned position and ignores `offset`, so a live drone could vanish while visible. The Interceptor never hit this because it was always off-screen and dashing (§2.6) |
| D7 | Phase 1 §2.4: the mover's `max_turn_rate` caps facing | Unchanged, but **it only turns the sprite**. A curved *path* is a brain-side request built with the new `Steering.turn_toward()` (§2.2). `1-context.md`'s "a capped turn rate produces the arc" is wrong | `EnemyMover.step()` sets velocity by `move_toward` and applies `max_turn_rate` to `rotation` only (review B2) |

### 2.1 Where things live

| Thing | Path | Kind |
|---|---|---|
| New steering primitives | `global/enemy_ai/steering.gd` (`Steering`) | pure static additions |
| `ContactProfile` | `global/components/contact_profile.gd` | `Node` child of an enemy, mirrors `DefenseProfile` |
| `ContactBlast` | `global/components/contact_blast.gd` | `HitBox` subclass, built in code, re-homed into the owner's parent |
| `SquadController` | `global/enemy_ai/squad_controller.gd` | `RefCounted` role board |
| `AnchorIdle` | `global/enemy_ai/anchor_idle.gd` | `RefCounted` helper owned by a brain |
| `EngagementBudget` | `global/enemy_ai/engagement_budget.gd` | `RefCounted` helper owned by a brain |
| `StateLight` | `global/components/state_light.gd` | `Node2D` presentation child (`Sprite2D`-based, code-built texture) |
| Swarm Drone | `assault/scenes/enemies/swarm_drone/` (`swarm_drone.tscn/.gd`, `swarm_drone_brain.gd`, `swarm_drone_config.gd/.tres`, `ENEMY.md`) | new enemy |
| Razor Drone | `assault/scenes/enemies/razor_drone/`: `git mv` of `drone_interceptor/`, classes renamed | evolved enemy |

Both enemies live under `assault/scenes/enemies/` even though they also fly in Open Space. This is because:
- `BaseEnemy` is still there until Ph15;
- five of the invariant gates discover the roster from that directory (`1-context.md` → *Gates*).

Nothing under `global/` references `ArenaCamera` or `BaseEnemy` (Phase 1 rule).

### 2.2 Steering additions (R2.2, R2.3, R2.7, and the overshoot curve)

All are pure functions returning a desired velocity, a direction or a scalar, unit-tested like Phase 1's nine
primitives.

- `spiral(pos, center, radius, angle, radius_rate, max_correct_speed)`: an orbit whose radius the caller shrinks or
  grows each tick. It carries the lead from its formation radius in to the burst start point.
- `corkscrew(pos, forward_dir, speed, amplitude, phase)`: forward motion plus a perpendicular sinusoid (`phase` is
  advanced by the caller). It replaces the look of the legacy `sine()` rails on approach, so entries are not straight
  lines.
- `formation_slot(pos, vel, anchor, heading, slot_offset, speed, decel)`: `arrive` at
  `anchor + slot_offset.rotated(heading.angle())`. This is what the flank slots use.
- `separation(pos, neighbours, radius)`, `alignment(vel, neighbour_vels)`, `cohesion(pos, neighbours)`: the three
  flocking terms. Neighbours are **squad mates only** (O(k²), k ≤ 7; finding 1).
- `clamped_lead_time(distance, speed, t_min, t_max)`: `clamp(distance / speed, t_min, t_max)`, which gives the
  0.4–0.8 s ram prediction (finding 5). A zero or negative speed returns `t_min`.
- **`turn_toward(current_dir, desired_dir, max_rate, delta) -> Vector2`** (new in rev 2, B2): rotates the unit
  vector `current_dir` toward `desired_dir` by at most `max_rate·delta` radians and returns a unit vector. It never
  overshoots the target angle, a zero `current_dir` returns `desired_dir` normalized, and a zero `desired_dir` returns
  `current_dir`. It is the only way a brain bends a path.

**Why a brain-side turn gives a bounded, real curve.** During an overshoot the brain requests
`turn_toward(actor.velocity.normalized(), dir_to_player, overshoot_turn_rate, delta) × overshoot_speed` **every tick,
starting from the actor's current velocity**, not from its own previous request. The mover then moves the velocity
along the straight segment from the current vector to that request (`move_toward`). Any point on that segment has a
heading between the two ends, so the actual heading turns by at most `overshoot_turn_rate·delta` per tick. That is
the bound the tests assert. The mover follows at steady state only if `overshoot_turn_rate × overshoot_speed ≤
acceleration`, so each config states that inequality and a config test pins it.

**Composition rule (Phase 1 §2.4, unchanged):** a brain makes **one** primary request per state. The flocking terms
are summed, capped at `flock_nudge_cap × max_speed` (0.35 **[judgement]**) and offered through `mover.add_nudge()`.
There is no weighted blend of all terms: that was rejected in Phase 1.

### 2.3 `ContactProfile` and `ContactBlast` (R2.14)

`ContactProfile` is a `Node` child that owns what touching this enemy does. It mirrors `DefenseProfile` (the
defensive side):
- `BaseEnemy._ready()` resolves the scene-authored `ContactProfile`, or creates a default.
- The default is `COLLISION`, which is exactly today's behaviour for every legacy enemy.

```
enum Mode { NONE, COLLISION, RAMMING, EXPLOSIVE }
@export var mode: Mode = COLLISION
@export var blast_radius: float = 0.0     # EXPLOSIVE only (px)
@export var blast_damage: int = 0         # EXPLOSIVE only
@export var blast_frames: int = 3         # EXPLOSIVE only; must be >= 2 (clamped with push_error)
signal contact_made(area: Area2D)         # one emit per registered touch
signal detonated(position: Vector2)       # EXPLOSIVE only, once
func setup(actor: Node2D, hit_box: HitBox, health: Health) -> void   # called by BaseEnemy; hit_box may be null
func set_armed(armed: bool) -> void       # RAMMING / EXPLOSIVE only; no-op for NONE / COLLISION
func is_armed() -> bool
func detonate() -> void                   # EXPLOSIVE: spawn one ContactBlast; idempotent
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

**The blast (rev 2, B1).** The rev-1 child blast could never land: it was freed with its owner in the same frame, it
sat at the canvas origin under a plain `Node`, and a one-frame deferred window is probably never stepped. The blast is
now a separate node that outlives the drone, following `ExplosionEffect.explode()`:

```
class_name ContactBlast extends HitBox       # global/components/contact_blast.gd
static func spawn(container: Node, at: Vector2, radius: float, damage: int, frames: int) -> ContactBlast
```

- `detonate()` resolves `container = actor.get_parent()`. If the actor is not inside the tree, there is no container:
  it pushes a warning, emits nothing and spawns nothing.
- `spawn()` builds the `ContactBlast` out of the tree: a `CollisionShape2D` with a `CircleShape2D(radius)`,
  `collision_layer = 256` (`enemy_hitbox`), `collision_mask = 0`, `monitorable = true`, `monitoring = false`,
  `damage`, `damage_type = CONTACT`. It stores `at`. It is added with **`container.add_child.call_deferred(blast)`**,
  because a detonation can happen inside an `area_entered` callback, where adding a physics body is refused.
  `_enter_tree()` sets `global_position = at`. It is set after parenting, for the same reason `ExplosionEffect` gives.
- **The blast owns its lifetime.** It stays monitorable for `frames` physics frames (default 3, minimum 2), counted in
  its own `_physics_process` on an integer counter, then calls `queue_free()`. There is no `create_timer` (brain rule
  and leak trap) and no deferred toggling: it is monitorable from the moment it enters the tree, so the first physics
  step after the flush sees it. The player's `HurtBox` (mask 1281 includes 256) detects it through its own
  `area_entered`, exactly like an `EnemyBullet`.
- `detonate()` is idempotent (a `_detonated` flag) and emits `detonated(at)` once, after the spawn is queued.
- The blast does **not** hit other enemies: enemy friendly fire is deferred (§8).

**When EXPLOSIVE detonates:**
- on a registered contact while armed;
- when the owner dies **while armed**: shooting a committed drone point-blank sets off its blast. This is the blast's
  real gameplay value, because the player's 0.5 s i-frames (`PlayerBase.invincibility_sec`) swallow a blast that lands
  on the same frame as the contact.
- Dying while unarmed never detonates.
- To hook death, `ContactProfile` connects to the `health` passed to `setup()` (`amount_changed`), so `BaseEnemy`'s
  death hook is not changed. The order against `BaseEnemy._on_health_changed` does not matter, because the blast is
  re-homed and keeps its own position.

**Other rules:**
- **Rails:** `BaseEnemy.suspend_ai()` calls `contact_profile.set_armed(true)`. A rail-driven Swarm Drone therefore
  hurts on contact exactly as the Kamikaze does today (C10). Legacy COLLISION is unaffected.
- **Contact death:** both new enemies connect `contact_made` to their own reaction:
  - Swarm → `health.set_health(0)`, so it is scored as a kill, which is Kamikaze parity. The contact already called
    `detonate()`, so the death path's `detonate()` is a no-op.
  - Razor → none. It survives, and its brain reads `contact_made` to know the dash *hit*.
  - `DroneInterceptor._on_contact_hit` goes away with the rename.
- The profile and the blast never write enemy motion. `BaseEnemy` is an ancestor swept by the single-writer gate, and
  `ContactBlast` is not an enemy.

### 2.4 `SquadController` (R2.5, R2.15)

A `RefCounted` **role board** (research approach S-B). It moves nothing. Members read it and request their own motion,
so the single-writer gate holds. It is **event-driven, not clocked**: roles are recomputed only on join, leave or
`release_lead()`. This removes the frame-guard problem the research raised (a second clock, and manual `_tick()`s not
advancing `Engine.get_physics_frames()`).

```
enum Role { NONE, LEAD, FLANK_LEFT, FLANK_RIGHT, REAR }
enum Side { LEFT, RIGHT, FRONT, BACK }      # sectors relative to the target's heading
signal role_changed(member: Node, role: int)
func join(member: Node2D) -> void           # connects member.tree_exiting -> leave(member)
func leave(member: Node) -> void            # explicit and idempotent; rail suspension calls it (rev 2, N3)
func role_of(member: Node) -> Role
func members() -> Array[Node2D]             # valid members only, join order
func rear_index(member: Node) -> int        # 0..n-1 among REAR members, for ring spacing
func claim_side(member: Node, preferred: Side) -> Side   # returns an unclaimed sector, latched until released
func release_side(member: Node) -> void
func release_lead(member: Node) -> void     # the lead finished its attack cycle: hand the token on
func update_target(position: Vector2, heading: Vector2) -> void   # rev 2 (N3): members report TargetInfo here
func set_engaged(member: Node, on: bool) -> void   # rev 2 (B3): hub idle, see §2.7.3
func is_engaged() -> bool                   # true while any valid member is engaged
var attack_window_open: bool                # set by the LEAD entering BURST, cleared when its burst ends
```

`target_position_hint` and `target_heading_hint` are the last values given to `update_target()`. The heading is the
target's velocity direction, or its `facing` when it is nearly still (below 20 px/s), as `TargetInfo` already gives it.

**Assignment** (deterministic, testable without physics):
- 1 member: `LEAD`.
- 2 members: `LEAD` + `FLANK_LEFT`.
- 3 or more: `LEAD`, `FLANK_LEFT`, `FLANK_RIGHT`, and the rest `REAR`.
- **LEAD** goes to the valid member closest to `target_position_hint`, with ties broken by join order. This is DOOM's
  "closest steals the token" (finding 2).
- **Flanks** go to the next two closest. Left versus right uses the sign of
  `target_heading_hint.cross(member_pos − target_position_hint)`. When the heading hint is zero, the direction from the
  squad centroid to the target stands in for it.

**Reassignment:**
- **The lead leaves** (dies, is freed, or is suspended by a rail and calls `leave()`): the board recomputes at once.
  Existing flanks keep their roles unless one of them becomes the new lead. In that case the closest REAR fills the
  vacated flank. This is "formation contracts" (IDEAS §17).
- **`release_lead()`:** the finishing lead drops to `REAR`, and the closest remaining member becomes `LEAD`.
- In Open Space this keeps the squad attacking in turns. In Assault each drone's `EngagementBudget` ends the rotation.

**Other rules:**
- **Membership is weak.** Members are checked with `is_instance_valid` and dropped on `tree_exiting`, and the board
  holds no strong reference to a `Node`.
- **Members hold the only strong reference** to the board, so when the last member is freed, the board is freed with
  it. Rev 1 claimed this without making it true in Assault (N3). §2.4.1 now makes it true: `WaveManager` keeps only a
  `WeakRef`.
- **Side claims** implement "chooses a side of the player that is not already occupied" (R2.4). Each attacker claims
  one sector and keeps it (the side latch, finding 1) until its pass ends. If the preferred sector is taken, the nearest
  free sector is returned. If all four are taken, the preferred one is returned (shared).
- **Engagement** is shared *state* on the board, not a message. Squad messaging (`TARGET_MARKED`, …) stays in Ph14.
  It exists so a hub squad engages together and returns to idle together (§2.7.3).

#### 2.4.1 Where squads come from

- **Assault:**
  - `WaveBuilder.SpawnConfig.squad(id: StringName)` is a new fluent hint, stored in a new `SpawnEntryResource.squad_id`.
  - A `formation()` entry is **automatically** one squad.
  - Loose entries in one `b.wave()` that share a `squad()` id form one squad.
  - A loose entry with no id gets a squad of one.
  - `WaveManager._expand_formation()` and `_trigger_wave()` write a **squad key** (a `String`,
    `"<wave index>:<id or formation entry index or spawn index>"`) into each spawn dict. They never write a board.
  - `_spawn_ship()` resolves the key in `_squads: Dictionary` (key → `WeakRef`). A live board is reused; a dead or
    missing one is replaced with a new board. It then sets `entity.set("squad", board)` before `add_child`, the same
    window `on_spawned` uses. `_squads` is cleared in `load_section()`.
  - So the dicts in `_waves` hold only strings, and a squad whose members have all died is released even while its
    section runs. A delayed member that spawns after all of its squad mates died starts a new squad of one; this is
    stated in the test.
  - Entities without a `squad` property ignore it (duck-typed through `in`).
  - Members join in their own `_ready()`, so staggered `delay()`s are fine.
- **Open Space:** `SectorHub` builds one board and hands it to each Swarm Drone it spawns. The hub keeps no reference.
- `EnemyBrain` gains nothing. The Swarm brain reads `actor.squad`; a `null` squad means "a squad of one" (§2.7.1).

### 2.5 `AnchorIdle`: the generic idle → combat handover (R2.16, R2.17)

A `RefCounted` helper a brain owns. It is generic, for Ph14.

```
var anchor: Vector2
var perceive_radius: float     # enter combat when the target is inside this, measured from the actor
var lose_radius: float         # leave combat when the target is outside this, measured from the actor (> perceive)
var notice_time: float         # the "noticed" beat before combat
var hold_combat: bool = false  # rev 2 (B3): an external reason to keep fighting; COMBAT never goes to RETURNING while set
func force_notice() -> void    # rev 2 (B3): IDLE or RETURNING -> NOTICING now (a squad mate saw the target)
func update(delta, actor_pos, target: TargetInfo) -> int   # returns IDLE / NOTICING / COMBAT / RETURNING
```

- **Hysteresis:** COMBAT → RETURNING only beyond `lose_radius`, so there is no flicker at the boundary (finding 7).
  RETURNING → IDLE on reaching `anchor` within the idle ring. RETURNING → NOTICING again inside `perceive_radius`.
- **Cheap while idle:** idle ticks do a squared-distance check only. There is no prediction and no squad queries.
- **No snap:** the brain never sets a velocity on the transition. It changes which request it makes, and the mover's
  `acceleration` / `braking` blend it. **What the test proves, honestly (N10):** the per-tick Δv bound
  (≤ acceleration·delta + ε) is mostly guaranteed by `EnemyMover.step()`'s `move_toward`. It fails only if the brain
  calls `halt()` or `boost()` on the transition, so it is a *guard* against those, not proof of a natural-looking
  turn. The tests also assert facing continuity: per-tick rotation change ≤ `max_turn_rate·delta` + ε.
- The idle *motion* belongs to the brain (§2.7.3, §2.8.4), not to `AnchorIdle`, which only decides *when*.
- **Assault skips idle:** a brain in a world with a provider (`EnemyWorld.arena(tree) != null`) starts in combat,
  because the level has already decided the fight is on.
- `perceive_radius >= lose_radius` is rejected: `push_error`, then `lose_radius = perceive_radius × 1.25`.

### 2.6 `EngagementBudget` and the Assault exit (C1, C2, C3)

The corridor forces re-entry (Phase 1), so without an exit an AI drone lives until killed. The fix: **the brain
decides, the mover releases, the world rect frees.**

- `EngagementBudget` (`RefCounted`) has `seconds`, `update(delta) -> bool expired`, and `active`. `active` is
  `EnemyWorld.arena(tree) != null`, so the budget does nothing in Open Space. It starts counting in the brain's first
  tick, which is the spawn frame.
- On expiry, the brain enters **DISENGAGE**:
  - it calls a new `EnemyMover.release_constraint()`, which sets `constraint = null` and records that it was released;
  - it sets `mover.max_speed = exit_speed`;
  - it requests `seek()` toward the **nearest point outside** `EnemyWorld.projectile_world_rect()` (straight to the
    nearest edge, rev 2: rev 1's `retreat_from(player)` did not bound the path length, N1);
  - it frees the actor once it is outside that rect (strict `<`/`>` compare, as in `_check_dash_end()`).
  - `release_constraint()` and the `max_speed` write are field writes on the mover, not motion writes, so they pass
    the single-writer gate. The gate's allowlist stays empty; the t6 test proves it still fails on a real velocity
    write.
- **Scoring** is unchanged: a drone that leaves has `was_killed == false`, so `ScoreTracker` counts it as escaped, the
  same as a Kamikaze leaving the bottom edge today.
- `MovementConstraint.inner_rect() -> Rect2` is new. The identity returns an empty rect, meaning "unbounded". The
  corridor returns its `visible` rect. Brains use it to keep an orbit *centre* inside the corridor (R2.13) without
  naming `ArenaCamera`.

**Budget values (rev 2, N1).**
- **Swarm `engage_seconds` 5.5 s.** Legacy rail drones are visible for about 3.4–3.6 s (research §3.6). One ram cycle
  is wind-up 0.4 + burst 0.45 + overshoot 0.8 = 1.65 s, so 3.5 + 1.65 ≈ 5.15 s, rounded up to 5.5 so a drone that
  spawns straight into FORM still gets one full attack. Rev 1 had 6.0, which broke the timeout below.
- **Swarm `exit_speed` 320 px/s.**
- **Razor `engage_seconds` 9.0 s [judgement]**: one full combat cycle plus a second. Razors spawn only in `deep_space`,
  which is a DURATION section, so no ENEMIES_CLEARED wait is affected.
- Both live in the configs.

**The deadline.** `LevelDirector._wait_enemies_cleared` starts its clock on `waves_complete`, which fires when the
last wave *triggers*. So the worst case is:

```
last_wave_max_delay + engage_seconds + exit_distance / exit_speed + exit_speed / (2 × acceleration) + margin
     0.8 s [computed]      5.5 s       804 px / 320 = 2.51 s          320 / 1200 = 0.27 s         0.5 s
                                                                                         total = 9.58 s < 10 s
```

- `last_wave_max_delay` is the largest `spawn_delay + slot.delay` in the last wave of every ENEMIES_CLEARED section
  (cloud_descent's last wave: 0.8 s **[computed]**).
- `exit_distance` is half the shorter side of `projectile_world_rect()` (1608 px square → 804 px): the worst distance
  from any point inside it to the nearest edge.
- The `exit_speed / (2 × acceleration)` term is the time lost accelerating from rest to `exit_speed`.
- **Test (t6, repointed at the config in t8b):** evaluates this formula from `_build_sections()` data, the live
  `projectile_world_rect()` size and the Swarm and Razor configs. It iterates **every** drone and razor spawn in
  ENEMIES_CLEARED sections, so adding a Razor to one later fails it.
- **Integration case (t15):** runs cloud_descent's last wave through a real `WaveManager` under a real `ArenaCamera`
  with a player stub, and asserts the enemy container holds no Swarm Drone before `enemies_cleared_timeout`.

### 2.7 Swarm Drone (R2.1–R2.7, R2.18)

Built in three tasks (review B4): **t8b** the solo cycle (§2.7.1), **t8c** the squad behaviour (§2.7.2), **t8d** the
hub idle (§2.7.3).

- **Scene:** `swarm_drone.tscn`, root `SwarmDrone extends BaseEnemy` with these children:
  - `Health`, `HurtBox`, `HitFlashAnimationPlayer`, `ContactHitBox`;
  - `ContactProfile` (EXPLOSIVE);
  - `Brain` (`SwarmDroneBrain`), `EnemyMover` (`AUTO`);
  - `StateLight`, `Sprite2D`.
- **Art and collision:** the art is the Kamikaze's `drones.png` cell until task `t12-art-swarm` replaces it. The
  collision circle is sized to a 32 px hull (r ≈ 13). The hurtbox and contact box share the body shape id and scale
  (gates).
- **Config:** `SwarmDroneConfig extends ShipConfig`, flat `@export_group`s. The task that first reads a field adds it.

  | Field | Value | Source | Task |
  |---|---|---|---|
  | `max_health` | 30 | Kamikaze parity | t8b |
  | `collision_damage` | 30 | Kamikaze parity (now actually applied, S10) | t8b |
  | `score_value` | 10 | Kamikaze parity | t8b |
  | Movement: `max_speed` 220, `acceleration` 600, `braking` 500, `max_turn_rate` 5.0 (sprite only) | | [judgement] | t8b |
  | Approach: `corkscrew_amplitude` 60, `corkscrew_frequency` 1.5 Hz | | [judgement] | t8b |
  | Attack: `windup_seconds` 0.4 | | finding 3 (≥ 0.34 s floor) | t8b |
  | Attack: `burst_speed` 480, `burst_seconds` 0.45 | | Interceptor dash speed; [judgement] | t8b |
  | Attack: `lead_time_min` 0.4, `lead_time_max` 0.8 | | IDEAS §5.1 | t8b |
  | Attack: `overshoot_seconds` 0.8, `overshoot_turn_rate` 2.4 rad/s, `second_passes` 1 | | IDEAS §5.1; 2.4 × 220 = 528 ≤ 600 (§2.2) | t8b |
  | Attack: `blast_radius` 48, `blast_damage` 15 | | [judgement] | t8b |
  | Exit: `engage_seconds` 5.5, `exit_speed` 320 | | §2.6 | t8b |
  | Squad: `rear_orbit_radius` 260, `rear_orbit_speed` 1.4 rad/s | | [judgement]: wide orbit | t8c |
  | Squad: `flank_distance` 200, `flank_angle_deg` 70 | | [judgement] | t8c |
  | Squad: `separation_radius` 30, `flock_nudge_cap` 0.35, `evade_radius` 90 | | finding 1 + [judgement] | t8c |
  | Squad: `rear_engage_seconds` 5.5 (= `engage_seconds`; a pre-approved t15 lever, §5 C3) | | §5 C3 | t8c |
  | Idle: `perceive_radius` 380, `lose_radius` 620, `notice_time` 0.35 | | [judgement] | t8d |
  | Idle: `idle_radius` 140, `idle_speed` 0.6 rad/s | | [judgement] | t8d |

  The brain copies the config values in `_ready()`, as the Interceptor did. The config holds no nested resources.
  A config test pins `overshoot_turn_rate × max_speed ≤ acceleration`.

#### 2.7.1 Solo cycle (t8b)

A drone with `squad == null` is a squad of one and its own LEAD.

`APPROACH → CLOSE_IN → WINDUP → BURST → OVERSHOOT → (WINDUP → BURST → OVERSHOOT)×second_passes → REJOIN`, plus
`DISENGAGE` (Assault only).

- **APPROACH:** `corkscrew` toward the player until inside `rear_orbit_radius + 100` (the constant 360 in t8b; t8c
  repoints it at the config). The corkscrew phase is drawn from `rng` (R2.3).
- **CLOSE_IN** (the solo LEAD's FORM): `spiral` inward from its current radius toward `flank_distance` (200 in t8b),
  then WINDUP.
- **WINDUP** (yellow light, `windup_seconds`):
  1. Claim a side (`claim_side` when there is a squad, preferring the sector the drone is already in).
  2. Lock `lead = clamped_lead_time(dist, burst_speed, 0.4, 0.8)`.
  3. Lock `aim = predicted_position(lead)`.
  4. With a squad, offset `aim` laterally by one hull width toward the claimed side, so two attackers do not converge
     on one point.
  5. Hold position and face `aim` (`hold_position` + `face_toward`).
- **BURST** (red light, profile armed): `mover.boost(dir_to_aim, burst_speed, burst_seconds)`. Touching the player →
  the EXPLOSIVE profile detonates → self-destruct (scored as a kill).
- **OVERSHOOT** (light off, profile disarmed; rev 2, B2): the burst ended without `contact_made`, which is a *miss*.
  For `overshoot_seconds`, every tick requests
  `Steering.turn_toward(actor.velocity.normalized(), dir_to_player, overshoot_turn_rate, delta) × max_speed`.
  At 2.4 rad/s over 0.8 s it turns up to about 110°: the "overshoots and curves away" arc. It never requests zero,
  so it never stops. The side claim is released.
- **Second pass:** if `passes_left > 0`, go back to WINDUP. Otherwise REJOIN: `release_lead()` when there is a squad,
  then CLOSE_IN (solo) or FORM (squad).
- **No player** (`has_target == false`): hold around the last known position.
- **DISENGAGE** (Assault): §2.6.
- **Assault adaptation (R2.6):** the same brain, with an `AUTO` mover (corridor). The `EngagementBudget` is active.
  The corridor's per-axis filter is what turns the orbits into "partial circles inside the lane". Brains clamp orbit
  centres to `inner_rect()` shrunk by the orbit radius, so an orbit near an edge does not fight the pressure. Spawns
  above, below or at the side of the screen enter through the corridor's not-entered rule (Phase 1).
- **Rails:** when suspended (station BOTTOM squad), the profile is armed permanently, the brain is inert, and the drone
  calls `squad.leave(self)` if it has a squad.

#### 2.7.2 Squad behaviour (t8c)

- Each tick, a member reports the target with `squad.update_target(target.position, target.heading)`.
- **FORM** (by role):
  - REAR: `orbit` at `rear_orbit_radius`, angle = `phase_offset + rear_index × TAU / rear_count`, where
    `phase_offset` is drawn from `rng` once, in `_ready()`.
  - FLANK_*: `formation_slot` at `flank_distance`, at ±`flank_angle_deg` off the target heading.
  - LEAD: CLOSE_IN (§2.7.1).
  - Every role adds the flocking nudge. "Player avoidance until commitment" is an `evade` nudge within `evade_radius`,
    applied only outside WINDUP/BURST.
- **Who attacks:**
  - The LEAD attacks on its own and sets `squad.attack_window_open = true` on entering BURST.
  - FLANKs start WINDUP when `squad.attack_window_open` becomes true, which gives the pincer.
  - REAR never attacks.
- **Reassignment mid-burst:** a member whose role changes during WINDUP/BURST/OVERSHOOT finishes its current pass,
  then goes to FORM in the new role. A member promoted to LEAD while in FORM goes to CLOSE_IN.
- **Budget per role:** in Assault a REAR member's budget is `rear_engage_seconds`. It is equal to `engage_seconds`
  by default and exists as a pre-approved lever for t15 (§5 C3).

#### 2.7.3 Hub idle (t8d) (rev 2, B3)

Open Space only; Assault skips idle (§2.5).

- Each member owns an `AnchorIdle` with the squad's **idle anchor**, which `SectorHub` sets through an exported
  `patrol_anchor` (it defaults to the spawn position, as for the Razor).
- **IDLE motion:** an `orbit` around the anchor at `idle_radius`, angle =
  `phase_offset + index × TAU / n + idle_speed × t`, with `index` the member's join order. The flocking nudge still
  applies. This is the "gentle formation drift" of IDEAS §18.5.
- **Squad-wide engagement:**
  - A member whose `AnchorIdle` reaches NOTICING or COMBAT calls `squad.set_engaged(self, true)`.
  - A member in IDLE or RETURNING that sees `squad.is_engaged()` calls `anchor_idle.force_notice()`. Brains tick in
    tree order, so every member is out of IDLE **by the end of the next physics tick** after the first perceives.
  - While `squad.is_engaged()`, every member sets `anchor_idle.hold_combat = true`, so no member returns alone.
  - A member beyond `lose_radius` calls `set_engaged(self, false)`. When no member is engaged, `hold_combat` clears
    and each member's `AnchorIdle` moves to RETURNING. The squad returns together.
- **NOTICING:** the yellow light blinks once and the drone faces the player for `notice_time`. It then enters
  APPROACH/FORM **from its current velocity**, with no `halt()` and no `boost()`.
- **RETURNING:** `arrive` at its idle slot, then IDLE.
- **Spawn safety (the Swarm's own radii):** see §2.11.

### 2.8 Razor Drone (R2.8–R2.13, R2.16)

#### 2.8.1 Step A (t9): rename, no behaviour change
- `git mv assault/scenes/enemies/drone_interceptor assault/scenes/enemies/razor_drone`.
- Files renamed to `razor_drone.*`, `razor_drone_brain.gd`, `razor_drone_config.*`. `.uid` sidecars travel with them
  (never hand-type a UID).
- Classes renamed to `RazorDrone`, `RazorDroneBrain`, `RazorDroneConfig`.
- `WaveBuilder.DRONE_INTERCEPTOR`/`drone_interceptor()` renamed to `RAZOR_DRONE`/`razor_drone()`.
- The rosters, `test_drone_interceptor.gd` → `test_razor_drone.gd`, `test_enemy_dual_mode.gd`, and the station guard's
  constant follow.
- Every existing pin stays green **unchanged in substance**.

#### 2.8.2 Step B (t10): combat
Evolve `RazorDroneBrain` to
`ENTER → ORBIT ⇄ REVERSE → (FEINT | WINDUP) → DASH → OVERSHOOT → RETURN → ORBIT`, with DISENGAGE in Assault.

- **Mover:** `acceleration` 900, `braking` 700, `max_turn_rate` 6.0 rad/s (sprite), `constraint_mode = AUTO`. The zeroes
  go away; this is the re-pin D5 names. **[judgement]**
- **ORBIT:** as today (`orbit_radius` 130, `orbit_speed` 1.8), plus an `orbit_dir` of ±1.
  - Each orbit window (the rng-drawn 1–2 s timer, as today) ends in a roll.
  - With `reverse_chance` (0.35 **[judgement]**, finding 6) the drone goes to **REVERSE**. REVERSE ramps its angular
    speed from `orbit_dir × orbit_speed` through 0 to `-orbit_dir × orbit_speed` over `reverse_seconds` (0.25), which
    is a visible brake. It then starts a new orbit window. A reversal can happen at most once per window.
  - Otherwise it rolls fake versus real: `fake_chance` 0.35 **[judgement]**.
- **FEINT** (fake dash; rev 2, N5 — the geometry is now specified):
  1. **FEINT_WINDUP:** yellow light for `windup_seconds × fake_windup_scale` (0.5 × 1.5 = 0.75 s), holding and facing the
     player (finding 4: a feint is a longer telegraph).
  2. **FEINT_LUNGE:** `boost(dir, feint_lunge_speed, feint_lunge_seconds)` with `dir` = the direction to the player
     rotated by `feint_offset_deg` toward `orbit_dir`. Values: 360 px/s, 0.45 s, 25° **[judgement]**. So it passes
     beside the player (closest approach ≈ 130 × sin 25° ≈ 55 px, clear of a 20 px hull plus the player's hull) rather
     than at them.
  3. **FEINT_BRAKE:** it requests zero velocity, so the mover's `braking` (700) stops it: about 360² / (2 × 700) ≈
     93 px more. Total travel ≈ 162 + 93 = 255 px. From orbit radius 130 this ends about 130–150 px from a stationary
     player, at a bearing about 130° from where the feint started: the far side.
  4. **WINDUP entry:** when speed drops below 40 px/s, the brain re-anchors `_orbit_angle` to its current bearing,
     flips `orbit_dir`, and enters the real WINDUP **at once**, with no orbit leg and no new roll.
  - **The profile is never armed and the white light is never shown** during a feint. At most one feint per cycle.
- **WINDUP** (real): yellow for `windup_seconds` (0.5, finding 3), then white commit flash for `commit_flash_seconds`
  (0.12). The white is exclusive to the real dash (R2.11, finding 4). The direction is locked at the start of the
  commit flash: `predicted_position(dash_prediction_time)` (0.2 s, as today).
- **DASH:** the profile is armed (RAMMING). `boost(dir, dash_speed, dash_seconds)`, where
  `dash_seconds = min((dist_to_locked_point + overshoot_px) / dash_speed, max_dash_seconds)`, with `overshoot_px` 120
  and `max_dash_seconds` 0.9. `contact_made` during the boost marks the dash as a **hit**.
- **OVERSHOOT** (rev 2, B2): disarm. Every tick requests
  `turn_toward(actor.velocity.normalized(), dir_to_player, overshoot_turn_rate, delta) × overshoot_speed`, with
  `overshoot_turn_rate` 3.0 rad/s and `overshoot_speed` 200 (= `approach_speed`; 3.0 × 200 = 600 ≤ 900). It leaves
  OVERSHOOT when its heading is within 20° of the bearing to the player, or after `overshoot_max_seconds` (1.2). The
  speed drops from 480 to 200 under `braking` while it turns; it never requests zero, so it never stops. If the dash
  was *not* a hit, it fires the pulse **exactly once** at OVERSHOOT entry:
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
- **Test seams:** `force_next_choice(&"real" | &"fake" | &"reverse")`, alongside the existing `_begin_dash()` seam.
  Tests never depend on a seed's luck for which branch runs.

#### 2.8.3 Config additions (flat)
`reverse_chance`, `reverse_seconds`, `fake_chance`, `fake_windup_scale`, `feint_lunge_speed`, `feint_lunge_seconds`,
`feint_offset_deg`, `windup_seconds`, `commit_flash_seconds`, `overshoot_px`, `max_dash_seconds`, `overshoot_speed`,
`overshoot_turn_rate`, `overshoot_max_seconds`, `pulse_damage`, `pulse_speed`, `engage_seconds`, `exit_speed`,
`side_lane_min_deg`, `side_lane_max_deg` (t10); `idle_radius`, `idle_radius_jitter`, `idle_speed`, `idle_speed_jitter`,
`perceive_radius`, `lose_radius`, `notice_time` (t11). A config test pins `overshoot_turn_rate × overshoot_speed ≤
acceleration`.

#### 2.8.4 Idle (t11) (§18.5, R2.16), Open Space only
- `AnchorIdle` runs around a patrol anchor (an exported `patrol_anchor`, defaulting to the spawn position).
  `perceive_radius` 450, `lose_radius` 700, `notice_time` 0.35 **[judgement]**.
- IDLE_ORBIT uses a slow orbit (`idle_radius` 160 ± 40 from `rng`, `idle_speed` 0.5 ± 0.2 rad/s, where the radius
  and speed are re-drawn each leg).
- Each leg lasts 2–4 s and ends in one of IDLE_BRAKE (0.6 s hold), IDLE_REVERSE (flip `orbit_dir`), or a short
  `boost` at 1.8 × idle speed. Each is equally likely, drawn from `rng`.
- On COMBAT, it goes to NOTICING (yellow light blinks once, faces the player for `notice_time`), then ENTER **from
  its current velocity**, with no `halt()` and no `boost()`. On RETURNING, it `arrive`s to the anchor and resumes
  IDLE_ORBIT.

### 2.9 Readability and sprites (R2.19)

- **`StateLight`** (`global/components/state_light.gd`, `Node2D` with one small `Sprite2D`):
  `set_state(OFF | ARMED | CHARGING | COMMIT)`, which maps to off / red / yellow / white. `blink_once()` is used by
  NOTICING.
  - **Texture (rev 2, N8):** built in code in `_ready()`, never scene-authored: a `GradientTexture2D` with
    `fill = FILL_RADIAL`, 8×8 px, white at the centre fading to alpha 0 at the edge. The state colour is applied
    through `modulate`. Because the texture is not in any `.tscn`, `test_entity_sprite_transparency.gd` does not see
    it. If a later task authors it in a scene, its transparent falloff still passes that gate. The unit test asserts
    a corner pixel of the generated image has alpha 0.
  - Only the light is recoloured. The hull keeps the faction palette (IDEAS §21.1).
  - Its brightness is capped below `EnemyBullet`'s (finding 9: projectiles must stay the most vivid thing on screen):
    `modulate.a ≤ 0.85` and 8 px at most.
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

1. **Swap under rails (t14).**
   - `WaveBuilder.DRONE` points at `swarm_drone.tscn`. Every existing `.move()` drone line, including the station's
     BOTTOM squad, now spawns a rail-driven Swarm Drone: armed profile, the same straight or sine path, the same
     cull.
   - Delete `kamikaze_drone/`. The level still plays as before, with new art and an explosion on contact.
   - The Bonus Drone is untouched (it has its own `BONUS_DRONE` constant and `_spawn_bonus_drone`).
2. **Rails off (t15).**
   - Remove `.move(...)` from **every** `b.drone()` line in `level_1_director.gd` (the t1 pin counts them) and from the
     two Razor lines (which already have none).
   - Keep `.at()`, `.formation()` and `.delay()` exactly. A `.free_after()` on a line that loses `.move()` is dropped
     too, since only a path mover reads it; the `EngagementBudget` replaces it.
   - Group into squads: formations automatically; loose drone lines in one wave share `squad(&"w<n>")` when the wave
     has 2–7 drones. The 7-drone wave is the largest, so squads stay within IDEAS' "3–6 + one".
   - The station BOTTOM squad **stays on rails**: the station is not in scope, and its tests pin a straight 170 px/s
     path.
   - The t1 characterization pin is updated to assert: triggers, offsets, delays and formation shapes are equal to the
     pinned list, and `movement == null` for every drone and razor spawn.

`SineMovement` and friends stay: other enemies still use them until Ph15.

### 2.11 Open Space hub (R2.22, R2.1) (rev 2: fixed bearings, N11 and B3)

- `SectorHub` loses `PATROL_DRONE`, `drone_count` and `_spawn_initial_drones()`. It gains `_spawn_patrol()` with:
  - `@export var patrol_seed: int = 0` (0 = randomize) → a local `RandomNumberGenerator` that seeds each drone's
    `brain.rng` (idle motion only);
  - `@export var squad_size: int = 4`;
  - `@export var patrol_ring_radius: float = 1000.0`;
  - `@export var swarm_anchor_bearing_deg: float = 90.0` (below the hub) and
    `@export var razor_anchor_bearing_deg: float = 270.0` (above it).
- **Why fixed bearings and 1000 px (rev 1 had a seeded angle on a 900 px ring).** The mission planets sit 654–742 px
  from the origin at bearings 30° (edelia), 149° (fortuna_station) and 216° (voeter_k05m), and the pickups line
  y ≈ −212 to −315 between x = −280 and 730. A seeded angle could put an idle Razor about 40 px from a planet, where
  the player's mission-trigger dwell (cancelled above 150 px/s) would start a fight. The two bearings are the
  planet-free arcs, and the anchors (0, 1000) and (0, −1000) keep every interactable out of reach.
- The anchor is the hub origin, the same as today (H1 in research §3.8). Each group idles around its own point on the
  ring.
- **Geometry, with each group's own radii** (all **[computed]** from `sector_hub.tscn` positions):

  | Group | Anchor | Worst idle offset | Its `perceive_radius` | Nearest of: player spawn (0,0) / planet / pickup | Clearance |
  |---|---|---|---|---|---|
  | Swarm | (0, 1000) | `idle_radius` 140 + separation slack 30 = 170 | 380 | fortuna_station 884 px | 884 − 170 = 714 > 380 |
  | Razor | (0, −1000) | `idle_radius` 160 + jitter 40 = 200 | 450 | `ModuleUnlockerEmpBlast` (−280, −315) 740 px | 740 − 200 = 540 > 450 |

  The spawn point is farther than both (1000 − 170 = 830; 1000 − 200 = 800).
- **A test pins this on the real `sector_hub.tscn`** (C4): for every direct child of `SectorHub` that is a planet
  instance or a pickup, and for the player's spawn position, `distance(anchor) − worst_idle_offset > perceive_radius`
  of that group. A pickup or planet moved later into a patrol's reach fails it.
- It spawns one Swarm squad (`squad_size` drones, one shared `SquadController`, `patrol_anchor` = the swarm anchor) and
  one Razor Drone (`patrol_anchor` = the razor anchor).
- Delete `open_space/scenes/entities/enemies/patrol_drone.{gd,tscn}` and `tests/integration/test_patrol_drone.gd`.
  Update `Steering.drift`'s comment.
- The hub tests that add `sector_hub.tscn` to the tree must stay green unchanged.
- Enemy bullets (the Razor's pulse) land in `EnemyContainer` through the existing grandparent rule (D4, pinned).
- The drones are 800+ px out, so they are usually off-screen at spawn. IDEAS §18.5's "visible before the encounter"
  is met when the player flies toward them; a nearer ring is a later tuning call (open question 2).

---

## 3. Build sequence

Each step is one task in `tasks.json` (same key).

1. **`t1-pin-drone-spawns`** (test): characterization before anything moves.
   - Pin level 1's drone and interceptor spawn list: trigger, offset, delay, formation type and size, and `movement`
     non-null for drones. Build it from `_build_sections()` data, not text.
   - Pin the station BOTTOM squad and the hub's current spawn (count 3, radius band 300–600).
   - Add **completeness guards** to `test_enemy_contact_damage.gd` and `test_contact_hitbox_geometry.gd`: every
     `<dir>/<dir>.tscn` BaseEnemy root in `assault/scenes/enemies` must be in the roster.
   - Compute level 1's peak concurrent drones per section under the legacy 3.5 s lifetime, from the pinned list, and
     assert the **[computed]** values (deep_space 14, planet_approach 6, cloud_descent 5).
2. **`t2-steering`**: §2.2 primitives, including `turn_toward`, and unit tests.
3. **`t3-contact-profile`**: §2.3, `ContactProfile` and `ContactBlast`. `BaseEnemy` resolves or creates the profile,
   `suspend_ai()` arms it, legacy is COLLISION. Unit tests plus the blast integration cases against a real player
   hurtbox. Every legacy pin stays green.
4. **`t4-squad-controller`**: §2.4 board and unit tests over fixture nodes.
5. **`t5-wave-squads`**: §2.4.1: `WaveBuilder.squad()`, formation → squad, `WaveManager` squad keys and the weak board
   map, with tests using a fixture scene that has a `squad` property.
6. **`t6-engagement-exit`**: `EngagementBudget`, `EnemyMover.release_constraint()`, `MovementConstraint.inner_rect()`
   and the corridor override, with the §2.6 deadline test.
7. **`t7-anchor-idle`**: §2.5 helper (including `hold_combat` and `force_notice`) and unit tests.
8. **`t8a-state-light`**: §2.9 `StateLight` and its unit test.
9. **`t8b-swarm-solo`**: §2.7 scene, config, rosters and §2.7.1 solo cycle, dual-mode.
10. **`t8c-swarm-squad`**: §2.7.2 squad behaviour, dual-mode.
11. **`t8d-swarm-idle`**: §2.7.3 hub idle on `AnchorIdle`.
12. **`t9-razor-rename`**: §2.8.1.
13. **`t10-razor-combat`**: §2.8.2, with the re-pins and the dual-mode spec.
14. **`t11-razor-idle`**: §2.8.4, on `AnchorIdle`.
15. **`t12-art-swarm`**, **`t13-art-razor`**: the sprites.
16. **`t14-swap-kamikaze`**: §2.10 step 1, and delete `kamikaze_drone/`.
17. **`t15-level1-ai`**: §2.10 step 2, the cloud_descent integration case and the C3 concurrency check.
18. **`t16-hub-patrol`**: §2.11, and delete PatrolDrone.
19. **`t17-docs`**: `updating-project-docs`, the per-enemy `ENEMY.md` files, `docs/enemy-roster.md`, the CLAUDE.md gate
    list, DECISIONS *as built*, and the dossier.

**Dependencies (rev 2).**
- Independent roots: t1, t2, t4, t7, t8a.
- t3 after t1 (the completeness guards must exist before `BaseEnemy` changes).
- t6 after t2, and t9 after t5: they edit the same files (`enemy_mover.gd`; `wave_builder.gd`). The runner is serial on
  one branch, but the order makes that explicit (N6).
- t8b needs t2, t3, t6 and t8a. t8c needs t8b and t4. t8d needs t8c and t7.
- The Razor chain (t9 → t10 → t11) starts after t8b, because both edit the same gate rosters. t10 also needs t8a.
- t14 waits on t9 (both rewrite the rosters, the t1 pin and `test_station_reinforcements.gd`).
- t15 needs t14, t5, t10 and t8c. t16 needs t8d, t11 and t4. t12 needs t8b; t13 needs t11 (both touch the Razor
  scene).

---

## 4. Test plan

Parameterized dual-mode tests use `use_parameters(["open_space", "assault"])` on a **string label**, and build the
harness inside the body (DECISIONS t12 leak trap). Mover-owned bodies are driven with `_tick()`. Every test sets
`rng_seed` or uses the `force_next_choice` seam. Run `scripts/check-test-leaks.sh` after every task that adds such
tests.

**Curve assertions (B2)** are made in the `open_space` harness, where no constraint filters velocity. In the `assault`
harness the overshoot cases assert the state sequence and the speed floor with the drone mid-corridor.

| File | Cases (boundary cases in **bold**) |
|---|---|
| `tests/integration/test_level1_drone_spawns.gd` (t1, updated in t14/t15) | Pinned spawn list equals the live one (14 drone formations, counted from data). Legacy peak concurrency per section = 14 / 6 / 5. After t15: `movement == null` for every drone and razor; triggers, offsets and delays unchanged. **A drone line re-given `.move()` fails** |
| `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd` (t1) | Completeness guard. **Temporarily removing a roster entry fails** (verified once by hand) |
| `tests/unit/test_steering.gd` (t2, extended) | spiral holds radius when `radius_rate = 0` and shrinks when negative; corkscrew's mean heading = forward over one period; formation_slot arrives and stops (**zero offset = arrive at anchor**); separation **zero with no neighbours** and **finite with a coincident neighbour**; alignment = mean velocity; cohesion toward the centroid; clamped_lead_time **clamps at both ends** and **speed 0 → t_min**; `turn_toward` turns by exactly `max_rate·delta` when far, **lands exactly on the target without overshooting when within one step**, turns the short way across ±π, **zero current → desired**, **zero desired → current**, always returns unit length |
| `tests/unit/test_contact_profile.gd` (t3) | Mode matrix; COLLISION always monitorable; RAMMING off at rest and on after `set_armed(true)` + one physics frame; EXPLOSIVE detonates on contact while armed; `detonate()` idempotent (one `detonated`, one blast node); `blast_frames < 2` is clamped with an error; the blast is in the **owner's parent**, at the owner's `global_position`, **still in the tree after the owner is freed**, and gone after `blast_frames` physics frames; `suspend_ai()` arms; **arming while already overlapping a player hurtbox registers exactly one hit** (engine pin, C5) |
| `tests/integration/test_contact_blast_damage.gd` (t3, new; B1) | A real player `HurtBox` (layer 128, mask 1281) wired to a real `Health` through the same path `PlayerBase` uses, i-frames not running. **An armed EXPLOSIVE fixture enemy placed so its contact box does not overlap the hurtbox but the blast radius does, then killed by `health.set_health(0)`, lowers the player's health by exactly `blast_damage`.** **The same enemy unarmed lowers it by 0.** Outside `blast_radius`: 0. **Detonation from inside an `area_entered` callback raises no "flushing queries" error.** `check-test-leaks.sh` is clean |
| `test_base_enemy.gd` (t3, extended) | Every legacy roster enemy resolves a COLLISION profile; the Bonus Drone resolves NONE or has no hitbox; the hurtbox masks are unchanged |
| `tests/unit/test_squad_controller.gd` (t4) | Roles for 1/2/3/6/**7**; the lead is closest to the hint; **the lead freed → the closest remaining becomes lead in the same call**; **explicit `leave()` behaves like a free and is idempotent**; a flank promoted to lead → a REAR fills the flank; left/right follow `target_heading_hint` (**a zero heading uses the centroid direction**); `release_lead` rotates; `claim_side` returns a free sector, **all four taken → the preferred one**; `is_engaged()` is true while any member is engaged and **false once the engaged member is freed**; **the last member freed → the board is released** (weakref null); `role_changed` arity |
| `tests/integration/test_wave_squads.gd` (t5) | A formation of 4 → one board shared by 4; two loose entries with the same `squad()` id → one board; no id → a board of one each; **the same id in two different waves → two boards**; an entity without a `squad` property spawns without error; **the spawn dicts hold no board** (only strings); **after every member of a squad is freed mid-section, its board's WeakRef is null**; a delayed member whose mates all died gets a fresh board |
| `tests/unit/test_engagement_budget.gd` + `test_enemy_mover.gd` + `test_assault_corridor_constraint.gd` (t6) | Budget inactive without a provider; expires at `seconds`; `release_constraint()` → outward velocity passes unfiltered; `inner_rect()` is empty for the identity and equals the visible rect for the corridor; **deadline: §2.6 formula < `enemies_cleared_timeout` for every ENEMIES_CLEARED section** (constants in t6, config values from t8b) |
| `tests/unit/test_anchor_idle.gd` (t7) | IDLE → NOTICING at `perceive_radius`; NOTICING → COMBAT after `notice_time`; **no flip between perceive and lose radius** (oscillate at 500 px for 5 s); RETURNING → IDLE at the anchor; **perceive ≥ lose rejected** (push_error and clamp); `force_notice()` from IDLE and from RETURNING; **`hold_combat` keeps COMBAT beyond `lose_radius`**, and clearing it returns RETURNING on the next update |
| `tests/unit/test_state_light.gd` (t8a) | Each state's `modulate`; OFF is invisible; `blink_once()` returns to the previous state; **the generated texture's corner pixel has alpha 0**; `modulate.a ≤ 0.85` in every state |
| `tests/integration/test_swarm_drone.gd` (t8b) | Dual-mode, solo: the ram aim equals `predicted_position(t)` with t ∈ [0.4, 0.8] (**far target → 0.8, near → 0.4**); a burst toward a stationary player uses `facing`; **overshoot curve** (open_space): during OVERSHOOT every tick's velocity-heading change is ≤ `overshoot_turn_rate·delta` + ε and has the sign that reduces the angle to the player's bearing (or is zero), the speed stays ≥ 0.5 × `max_speed`, and the heading has turned ≥ 60° by the end (player placed 90° off the burst line); a miss → OVERSHOOT → exactly one more pass → REJOIN; contact while armed → detonates, frees, scores as a kill; **no contact damage in CLOSE_IN** (touching the player unarmed deals 0); **the drone's blast hurts a real player hurtbox when the armed drone is shot within `blast_radius`**. Config: `overshoot_turn_rate × max_speed ≤ acceleration`. Assault only: the budget → DISENGAGE → freed outside the world rect, **never before `engage_seconds`**; a below-screen spawn enters; a burst toward an edge stays inside the hard band. Rail: an `EnemyPathMover` suspends → armed |
| same file (t8c) | Dual-mode, squads: REAR holds `rear_orbit_radius` ± 10 %; **two attackers never claim the same side**; the flanks start WINDUP only after the lead's BURST opens the window; **no contact damage while in FORM**; role reassignment after the lead is freed mid-burst (the promoted member finishes nothing it had not started, and the vacated flank is filled); formation recovery (displace every member 150 px, all are back within tolerance of slot or ring within 3 s); **phase offsets (N4):** with `flock_nudge_cap = 0` and distinct `rng_seed`s, the members' `phase_offset` and corkscrew phases are pairwise different, and **with the same seed they are equal** (the control that proves the phase comes from `rng`); a rail-suspended member calls `leave()` and the squad reassigns; in Assault a REAR member honours `rear_engage_seconds` |
| same file (t8d) | Open Space idle: members stay within `idle_radius` + 30 of the anchor over 20 s; **one member moved inside `perceive_radius` → every member is out of IDLE by the end of the next tick**; hysteresis (the target at a distance between perceive and lose radius for 5 s: no member returns); **one member beyond `lose_radius` while another is engaged → it does not return**; all beyond `lose_radius` → all RETURNING, then IDLE at their slots; handover guard: per-tick Δv ≤ acceleration·delta + ε and per-tick rotation change ≤ `max_turn_rate·delta` + ε across NOTICING → combat; Assault harness: no idle, starts in APPROACH |
| `tests/integration/test_razor_drone.gd` (t9 rename, t10/t11 extend) | t9: every old pin green under the new names. t10 (dual-mode): orbit radius; **reversal changes the sign of angular velocity through zero, never instantly**; the fake shows CHARGING for 1.5× the windup, **never COMMIT, never arms**; **the fake ends on the opposite side** (bearing differs by > 120°) and enters WINDUP without an orbit leg; the real dash shows CHARGING → COMMIT → armed; dash direction = locked prediction; **overshoot curve** (open_space, same assertion shape as the Swarm's, floor 0.5 × `overshoot_speed`); a missed dash → **exactly one** pulse bullet acquired from the pool; **a hit dash → zero pulses**; it survives the dash (not freed); Assault: the dash bearing is in the side lane, the budget exit, and **the orbit centre stays inside `inner_rect()` shrunk by `orbit_radius` with the player placed within `orbit_radius` of a corridor edge** (N9: mid-screen cannot fail). Config: `overshoot_turn_rate × overshoot_speed ≤ acceleration`. t11 (Open Space): idle stays within the anchor ring; brake/reverse/boost all occur over a seeded 30 s; handover guard (Δv and rotation, as t8d); hysteresis; returns to idle beyond `lose_radius` |
| `test_enemy_dual_mode.gd` (t9/t10) | Interceptor cases renamed, then rewritten as Razor cases: "identical in both modes" becomes "identical relative to the constraint" |
| `test_station_reinforcements.gd` (t14) | BOTTOM squad = 2 × `swarm_drone.tscn` on rails, the same path; **a rail swarm drone touching the player deals `collision_damage`** |
| `test_level1_drone_spawns.gd` + new `tests/integration/test_level1_drone_exit.gd` (t15) | C3 concurrency (§5); **cloud_descent's last wave, run through a real `WaveManager` under a real `ArenaCamera` with a player stub, leaves no Swarm Drone in the container before `enemies_cleared_timeout`** (N1) |
| `tests/integration/test_sector_hub_patrol.gd` (t16) | One squad of `squad_size` Swarm Drones + one Razor; seeded positions are reproducible; **§2.11 clearance for every planet, pickup and the player spawn, per group**; nobody perceives the player at frame 0; **no `PatrolDrone` / `patrol_drone` reference in any `.gd`, `.tscn` or `.tres` under `res://`** (N12: docs may name it); a Razor pulse bullet's parent is `EnemyContainer` (D4) |
| Existing gates (all tasks) | `test_enemy_hurtbox_geometry`, `test_config_instance_isolation` (floor 10 still holds: −kamikaze +swarm, a rename is net 0), `test_entity_sprite_transparency` (floor 12), `test_enemy_mover_single_writer` (both brains and the squad), `test_signal_emit_arity` (`contact_made`, `detonated`, `role_changed`), `test_project_load_integrity`, `test_resource_uid_integrity`, the Bonus Drone pins **unchanged** (R2.18) |

What the gate **cannot** show: whether the swarm is fun, whether level 1's density feels right, and whether the lights
read at speed. t15 and t16 end with a written hand-playtest checklist in their final message. t16's checklist includes
"dwell at each planet's mission trigger and at the pickups: no patrol engages" (N11). The dossier lists these as known
gaps.

---

## 5. Risks

| Id | Risk | Mitigation |
|---|---|---|
| C1/C2 | AI drones never leave the corridor, or stall sections | §2.6 budget + release + nearest-edge exit + world-rect free; the deadline test (9.58 s < 10 s) and the t15 integration case |
| C3 | Level-1 difficulty spike (drones live about 8.3 s instead of about 3.5 s) | See the table below. The thresholds and the levers are decided **now** |
| C4 | Hub ambush at spawn, or at a planet | §2.11 fixed bearings + per-group clearance test over every interactable |
| C5 | Area arm and disarm timing | Pinned engine behaviour (t3); `set_deferred` for arming; the blast is monitorable from `_enter_tree` and lives ≥ 2 frames |
| C6 | Squad dangling references | Weak membership, `tree_exiting`, `leave()`, RefCounted lifetime, `WaveManager` keeps only WeakRefs (t4, t5 tests) |
| C7 | Nondeterminism | `brain.rng`, `patrol_seed`, `force_next_choice` seams |
| C8 | Deleting scenes breaks load/UID gates or docs | Completeness guards first (t1); `git mv` for the rename; deletions in their own tasks (t14, t16) |
| C9 | The corridor has never been played with real AI | The Razor re-pins the edge behaviour; band values unchanged unless a test shows why |
| C10 | Rail Swarm must still hurt | `suspend_ai()` arms (t3), tested on the real station spawn (t14) |
| C11 | Art budget | Two generations + fix pass; state via `StateLight`, not extra frames |
| C12 | The explosive blast near the player feels unfair | The blast only fires when armed (red light), radius 48 is under 2 hull widths, damage 15 is half the contact damage. Tunable in `.tres` |
| C13 | The rename touches many files in one commit | Its own task (t9) with no behaviour change, so a failure is attributable |
| C14 | The brain-side curve fights the corridor near an edge | Curve assertions run in open_space; the assault harness asserts the sequence and speed floor; the per-axis filter only removes the outward component |

**C3 concurrency, computed now (rev 2, N2).** Peak simultaneous drones (Swarm + Razor) per section, from
`_build_sections()` with each drone alive for a fixed lifetime after its spawn time. "Attack-capable" counts only
LEAD and FLANK members (the first three of each squad); REAR members never attack. **[computed]**

| Section | Squads (size: count) | Legacy peak (3.5 s) | New peak, all (9.1 s) | New peak, attack-capable (9.1 s) | Ratio all / capable |
|---|---|---|---|---|---|
| deep_space | 1:3, 2:7, 3:6, 4:2, 6:1, 7:1 | 14 | 23 | 19 | 1.64 / 1.36 |
| planet_approach | 1:2, 2:5, 3:5, 4:2, 5:3, 6:2 | 6 | 9 | 8 | 1.50 / 1.33 |
| cloud_descent | 1:3, 2:2, 3:3, 4:2, 5:3 | 5 | 10 | 7 | 2.00 / 1.40 |

9.1 s is rev 1's 6.0 s plus the worst exit; rev 2's 5.5 + 2.8 = 8.3 s is a little lower. The rule for t15:
- **Metric:** the attack-capable peak against the legacy peak, because every legacy drone was a rammer and a REAR
  drone is not. The all-drones peak is recorded too.
- **Pre-approved levers** t15 may pull without escalating, in this order:
  1. lower `rear_engage_seconds` toward 3.5 s (legacy parity; REAR members never attack);
  2. lower Swarm `engage_seconds` to no less than 4.5 s;
  3. split a loose wave of 6–7 drones into two squads (`squad(&"w<n>a")`/`b`).
- **Escalate** (`Result: ESCALATE`) only if, after those levers, any section's attack-capable ratio exceeds 2.0 or its
  all-drones ratio exceeds 2.5. On the computed numbers neither happens, so t15 is expected to pass with no lever.
- The t15 test asserts both ratios per section, so a later spawn change that breaks them fails the gate.

---

## 6. Requirements coverage

| Req | What | Task(s) |
|---|---|---|
| R2.1 | Swarm replaces Kamikaze and PatrolDrone, 24–36 px | t8b, t12, t14, t16 |
| R2.2 | Lightweight flocking + player avoidance + lateral offset | t2, t8c |
| R2.3 | Per-drone phase offsets | t8b (corkscrew phase), t8c (rng phase + rear spacing; tested with a same-seed control) |
| R2.4 | Coordinated ram: orbit → 0.4–0.8 s prediction → free side → burst → overshoot → one second pass | t2, t4, t8b, t8c |
| R2.5 | Lead / flanks / rear, reassignment on lead death | t4, t8c |
| R2.6 | Swarm in the Assault corridor | t6, t8b, t8c, t15 |
| R2.7 | spiral / corkscrew | t2 |
| R2.8 | Razor evolves the Interceptor, 40–56 px, full state chain | t9, t10, t13 |
| R2.9 | Orbit reversal | t10 |
| R2.10 | Fake dash, attack from the opposite side | t10 |
| R2.11 | The real dash's cue is stronger than the fake's | t8a (`StateLight`), t10. **Audio: out of scope** (no SFX pipeline for enemies; §8) |
| R2.12 | Contact damage + pulse after a missed dash | t3, t10 |
| R2.13 | Razor in Assault: orbit band, side-lane diagonal attack | t6 (`inner_rect`), t10 |
| R2.14 | Contact profiles None / Collision / Ramming / Explosive | t3 (Armour collision → Ph4) |
| R2.15 | SquadController with roles; formations only as spawn layouts | t4, t5, t8c, t15 |
| R2.16 | Razor idle + generic handover | t7, t11; the Swarm squad's idle on the same contract: t8d |
| R2.17 | Idle cheaper than combat | t7 (squared-distance only while idle; tested by construction: no TargetInfo prediction calls) |
| R2.18 | Retire Kamikaze and PatrolDrone, keep the Bonus Drone | t14, t16; the Bonus Drone pins stay unchanged in every task |
| R2.19 | Readability: silhouette, faction accents, one light per state | t8a (`StateLight`), t12, t13 |
| R2.20 | Deterministic dual-mode tests over the listed behaviours | t8b, t8c, t8d, t10, t11 (§4) |
| R2.21 | §41 Phase 2 items 1–2 | the whole epic. Items 3–4 (Fighter, Gatling) → **Phase 3** |
| R2.22 | Hub ambient spawn → Swarm squad + Razor | t8d, t16 |
| R2.23 | Level-1 migration, layouts and timing preserved | t1, t14, t15 |
| R2.24 | Gates cover the new scenes | t1 (guards), t8b, t9, t10, t14 (rosters) |
| §3.2 other primitives (regroup, break_contact, lead_target) | | later phases 3, 4, 14 (DECISIONS) |
| §16 Armour collision | | **Phase 4** (Ram Corvette) |
| §17/§35 for non-drone enemies, §18 messages | | **Phase 14** (squads for fighters in Phase 3 reuse `SquadController`) |
| §18.5 idle for other families | | **Phase 14** |
| §2/§38 Salvage Drone Open Space event | | **Phase 13** (EncounterDirector) |
| §21–23 for other enemies, audit | | **Phase 17** |
| §32 EncounterDirector, §33 leash / search | | **Phase 13** (only the idle `lose_radius` return exists here) |
| Other level-1 enemies off rails | | **Phase 15** |
| Enemy friendly fire from blasts | | out of scope: no design decision exists; the blast's layer is fixed at 256 |
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
2. **Hub patrol distance:** the patrols idle 1000 px above and below the hub, clear of every planet and pickup, and
   usually off-screen until you fly toward them. A nearer ring is a config change (`patrol_ring_radius`), and the
   clearance test says whether it is still safe.
3. **Assault squads for loose drone lines** are grouped by wave. If a specific wave should behave as independent
   drones, drop its `squad()` hint.

---

## 9. Response to feedback (review round 1)

| Finding | What changed |
|---|---|
| **B1** blast freed with its owner, at the origin, one un-stepped frame | New `ContactBlast` (§2.3): spawned into the owner's parent at the owner's position via a deferred `add_child`, monitorable from `_enter_tree`, alive for `blast_frames` (default 3, min 2) physics frames on its own counter, then freed. New `test_contact_blast_damage.gd` (t3) and a t8b case assert **player health actually drops** by `blast_damage` for an armed kill and not for an unarmed one, plus no flushing-queries error and a clean leak check |
| **B2** `max_turn_rate` only turns the sprite | New `Steering.turn_toward()` (t2) and a brain-side curve built from the actor's current velocity every tick (§2.2, D7). Swarm and Razor OVERSHOOT specified with their own turn rates and speeds, and the `turn_rate × speed ≤ acceleration` inequality pinned per config. Each drone's spec asserts the per-tick heading bound, the turning sign, a speed floor and a minimum total turn |
| **B3** Swarm hub idle owned by nobody | New task **t8d-swarm-idle** (depends on t7 and t8c). Config fields and values added (§2.7). `SquadController.set_engaged()/is_engaged()` and `AnchorIdle.hold_combat/force_notice()` give squad-wide engage and return. The spawn inequality is redone per group with the Swarm's own radii (§2.11), and t8d has the requested cases (one perceives → all leave IDLE by the next tick; hysteresis; return beyond `lose_radius`; the handover guard) |
| **B4** t8 too big | Split into **t8a-state-light** (small), **t8b-swarm-solo** (large), **t8c-swarm-squad** (large) and t8d. t9 depends on t8b, t10 on t8a, t15 and t16 on t8c (t16 through t8d) |
| **N1** deadline ignored the last wave's delay | Swarm `engage_seconds` 6.0 → 5.5, `exit_speed` 260 → 320, DISENGAGE seeks the nearest edge. The formula now includes the last-wave delay, the acceleration ramp and a 0.5 s margin: 9.58 s < 10 s (§2.6). A t15 integration case runs the real last wave |
| **N2** C3 threshold a coin toss | Peaks computed now (§5 table). The metric is the attack-capable peak; the pre-approved levers and the escalation thresholds are fixed in advance |
| **N3** `SquadController` API gaps | `leave()` and `update_target(position, heading)` added. `WaveManager` stores only squad keys in the spawn dicts and a `WeakRef` map, so members really hold the only strong reference (§2.4.1), with test cases for it |
| **N4** phase-offset test cannot fail | Rewritten: with separation off and distinct seeds the phases differ, and a same-seed control shows they are equal (§4, t8c) |
| **N5** feint geometry | Lunge direction, speed, duration and offset specified; brake distance and end bearing worked out; WINDUP starts at once when speed drops below 40 px/s (§2.8.2) |
| **N6** shared files without ordering | Added t6 → t2 and t9 → t5 |
| **N7** grep catches `.claude/`; 13 vs 14 formations | t9's grep excludes `.claude/`. The count is corrected to 14 at the top of this plan and is counted from data by t1 |
| **N8** `StateLight` texture | A code-built radial `GradientTexture2D` with a transparent edge (§2.9), with a corner-alpha assertion |
| **N9** inner-rect case cannot fail mid-screen | The case now places the player within `orbit_radius` of a corridor edge |
| **N10** the Δv bound is mostly guaranteed | Stated as a guard against `halt()`/`boost()`, not proof (§2.5). Facing continuity is asserted too |
| **N11** hub ring near the planets | Fixed bearings in the planet-free arcs at 1000 px, a clearance test over every planet, pickup and the spawn point, and a checklist item in t16 |
| **N12** PatrolDrone sweep scope | Limited to `.gd`, `.tscn` and `.tres` |
