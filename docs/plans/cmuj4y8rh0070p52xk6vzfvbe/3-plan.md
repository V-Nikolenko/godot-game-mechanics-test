# Swarm Drone solo cycle (t8b) — plan

Task `cmuj4y8rh0070p52xk6vzfvbe`, epic `cmufs7ek60001nm2x6d0bt2et`. The epic plan (`3-plan.md` §2.7, §2.7.1, §2.6,
§4 t8b row) is approved and is **not** re-derived here. This plan pins what the epic plan leaves open for t8b, and
fixes the one numeric contradiction review round 2 raised (B5) that was never folded into the epic plan.

## Problem

Nothing in the game is a Swarm Drone yet. After this task a single Swarm Drone exists as a scene that can be dropped
into either mode: it corkscrews in, spirals close, holds and winds up with a yellow light, rams the point the player
will be at with a red light (hurting only then), and on a miss curves round — never stopping — for exactly one more
pass before it re-forms. In Assault it leaves the arena by the nearest edge after 5.5 s. Nothing spawns it in a level
yet (t14/t15/t16 do that).

## Design

### Files (all new unless stated)

| Path | Content |
|---|---|
| `assault/scenes/enemies/swarm_drone/swarm_drone_config.gd` | `class_name SwarmDroneConfig extends ShipConfig`, flat `@export_group`s: Movement / Approach / Attack / Exit — exactly the t8b rows of the epic §2.7 table, with the B5 change below |
| `.../swarm_drone_config.tres` | Values: 30 HP, 30 collision, 10 score; `max_speed` 220, `acceleration` 600, **`braking` 900**, **`max_turn_rate` 10.0**; **`corkscrew_amplitude` 120 (px/s), `corkscrew_frequency` 0.6**; `windup_seconds` 0.4, `burst_speed` 480, `burst_seconds` 0.45, `lead_time_min` 0.4, `lead_time_max` 0.8, `overshoot_seconds` 0.8, `overshoot_turn_rate` 2.4, `second_passes` 1, `blast_radius` 48, `blast_damage` 15; `engage_seconds` 5.5, `exit_speed` 320 |
| `.../swarm_drone_brain.gd` | `class_name SwarmDroneBrain extends EnemyBrain`, enum phases, below |
| `.../swarm_drone.gd` | `class_name SwarmDrone extends BaseEnemy`; `@export var config: SwarmDroneConfig = preload(...)`; `var squad: SquadController` (duck-typed slot `WaveManager` already writes); `_ready()`: `super()`, group `enemies`, copy config → health, contact hitbox damage, profile blast fields, mover limits, brain fields; `contact_profile.contact_made → health.set_health(0)` (guarded `> 0`); join the squad if one was set (`update_target` first, N14). **No `_physics_process` override** (BaseEnemy's tick runs the brain) |
| `.../swarm_drone.tscn` | Root `SwarmDrone` (CharacterBody2D, `sprite_forward_angle = -PI/2`, nose-up art). Children: `Sprite2D` (`drones.png`, `region_enabled`, `Rect2(0,0,42,42)` — the sheet is a 3×2 grid of 42×42 cells; nose direction checked by eye before fixing `sprite_forward_angle`, one cell — placeholder until t12), `CollisionShape2D` (one `CircleShape2D` sub-resource r 13 → 26 px across ≈ a 32 px hull), `HurtBox` (layer 512, mask 97 like the interceptor, same shape id and scale), `Health`, `HitFlashAnimationPlayer` (hit flash as the interceptor's), `ContactHitBox` (layer 256, mask 128, damage 30, CONTACT, same shape id and scale), `ContactProfile` (mode EXPLOSIVE, blast 48 / 15 / 3 frames), `EnemyMover` (AUTO, `turn_lerp` 20), `Brain` (`SwarmDroneBrain`), `StateLight` (at the nose) |
| `.../ENEMY.md` | Per-entity doc |

`config` fields the scene's nodes also carry (profile blast, mover limits) are **overwritten from the config in
`_ready()`** so the `.tres` is the single source of truth (CLAUDE.md "the `.tres` value wins").

### B5 resolution (numeric; recorded in DECISIONS)

Review round 2 showed that with `braking` 500 the overshoot request (220 px/s against a 480 px/s start) spends
0.52 s of the 0.8 s window braking along the old heading and turns only ~44°, while the AC demands ≥ 60°. Chosen fix:
**`braking` 900** (reviewer's replay: ~76°; the ram cycle length and the §2.6 deadline, which uses `acceleration`, are
unchanged). A config test pins **both**:
- steady state: `overshoot_turn_rate × max_speed ≤ acceleration` (2.4 × 220 = 528 ≤ 600) — the task's AC;
- with the braking phase: `overshoot_turn_rate × (overshoot_seconds − (burst_speed − max_speed) / braking) ≥
  deg_to_rad(60)` → 2.4 × (0.8 − 0.289) = 1.23 rad ≈ 70° ≥ 1.047.

The epic's "turns up to about 110°" sentence is corrected in DECISIONS.

### Brain: `SwarmDroneBrain`

`enum Phase { APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT, REJOIN, DISENGAGE }`.
`signal phase_changed(phase: int)` — emitted on every transition (tests and later tasks observe the sequence; arity
gate covered). Public read-only state for tests: `phase`, `passes_left`, `aim`, `lead_time`, `burst_count`.

Every tick: `var target := TargetInfo.player(get_tree())`; `budget.update(delta)`.

| Phase | Request | Exit |
|---|---|---|
| APPROACH | `request_velocity(Steering.corkscrew(pos, dir_to_player, max_speed, corkscrew_amplitude, _cork_phase))`, `_cork_phase += TAU·corkscrew_frequency·delta`; `_cork_phase` starts at `rng.randf_range(0, TAU)` (R2.3) | distance ≤ `APPROACH_EXIT_RADIUS` 360 → CLOSE_IN |
| CLOSE_IN | `mover.spiral(player, _ring, _ring_angle, 0.0, max_speed)` — **`radius_rate` 0**: the inward motion comes only from `_ring`, which starts at the current distance and shrinks at `CLOSE_IN_SHRINK_SPEED` 120 px/s to `CLOSE_IN_RADIUS` 200 (review N2: never both). `_ring_angle` starts at the drone's bearing from the player and advances at `CLOSE_IN_TANGENT_SPEED / _ring` (130 px/s, so the anchor never outruns `max_speed` 220), direction sign from `rng` | `_ring` reached and \|dist − 200\| ≤ 30, or `CLOSE_IN_MAX_SECONDS` 2.5 elapsed → WINDUP (subject to the budget gate below); distance > 460 → APPROACH |
| WINDUP | light CHARGING. On entry: `_hold_at = pos + v·\|v\| / (2·braking)` (the stopping point, review N1); with a squad, `claim_side(actor, sector the drone is in)`. Each tick: `mover.hold_position(_hold_at, 4, max_speed)`, compute `lead_time = Steering.clamped_lead_time(dist, burst_speed, lead_time_min, lead_time_max)` and `aim = target.predicted_position(lead_time)` (+ one hull width, 32 px, lateral toward the claimed side, squad only), `mover.face_toward(aim)` | `windup_seconds` elapsed → BURST, with `aim` from that last tick **locked** |
| BURST | On entry: `contact_profile.set_armed(true)`, light ARMED, `mover.boost(aim − pos, burst_speed, burst_seconds)`, `burst_count += 1`. Then nothing (the boost ignores requests) | `not mover.is_boosting()` → OVERSHOOT (a contact would already have freed the drone) |
| OVERSHOOT | On entry: disarm, light OFF, `release_side`. Each tick: `request_velocity(Steering.turn_toward(actor.velocity.normalized(), dir_to_player, overshoot_turn_rate, delta) × max_speed)` — rebuilt from the **actor's current velocity** every tick, never zero | `overshoot_seconds` elapsed → `passes_left > 0` ? (`passes_left -= 1`, WINDUP) : REJOIN |
| REJOIN | One tick: with a squad of **two or more**, `release_lead(actor)` (a squad of one keeps its LEAD — see below); `passes_left = second_passes` | → CLOSE_IN (or APPROACH if beyond 460 px) |
| DISENGAGE | On entry: disarm, light OFF, `squad.leave(actor)` if any, `mover.release_constraint()`, `mover.max_speed = exit_speed`, pick the nearest edge of `EnemyWorld.projectile_world_rect()` **once, on entry** (N8; any point of the rect is ≤ 804 px from its nearest edge, which is the formula's bound). Each tick: `mover.seek(point 64 px beyond that edge, exit_speed)` | actor strictly outside the rect → `actor.queue_free()` |

- **Configuration timing (review B1).** Godot readies the `Brain` child before its `SwarmDrone` parent copies the
  config onto it, so the brain derives nothing from its tunables in `_ready()` (only the rng-drawn corkscrew phase and
  spin sign, which depend on `rng_seed`, not on config). The `EngagementBudget` (`EngagementBudget.new(engage_seconds,
  get_tree())`) and `passes_left = second_passes` are built on the brain's **first tick** — which is also what epic
  §2.6 says ("it starts counting in the brain's first tick").
- **Budget and BURST (review B3).** Rather than defer DISENGAGE through a burst (which would add `burst_seconds` and a
  480 px/s reversal to the §2.6 deadline and push it past 10 s), the brain **never starts a WINDUP it cannot finish
  before the budget expires**: WINDUP is entered only while `budget.remaining() ≥ windup_seconds + burst_seconds +
  (burst_speed − max_speed) / braking` (0.4 + 0.45 + 0.29 = 1.14 s). A drone that would otherwise wind up keeps
  circling in CLOSE_IN (or, after an OVERSHOOT, goes to REJOIN). So the budget can only expire in
  APPROACH / CLOSE_IN / OVERSHOOT-tail / REJOIN, at a speed ≤ `max_speed` 220 — the same assumption the §2.6 formula
  already made — and DISENGAGE begins **exactly** at `engage_seconds`. The formula and its 9.58 s stand unchanged.
  Needs one small addition: `EngagementBudget.remaining() -> float` (`INF` when inactive), with a unit case.
- **Facing:** APPROACH/CLOSE_IN face the direction of travel (mover default); WINDUP faces `aim`; BURST/OVERSHOOT
  face travel. Review B4 showed that `turn_lerp` 10 capped at 5 rad/s leaves 0.066 rad at 90° and 1.14 rad at 180°
  after the 0.4 s wind-up, so the mover gets **`turn_lerp` 20** and the config **`max_turn_rate` 10 rad/s** (a
  180° turn takes 0.31 s < 0.4 s): the wind-up telegraph must actually point where the burst goes, from any entry
  angle, including a second-pass WINDUP that starts ~100° off.
- **No player** (`has_target == false`): `hold_position(last known position or own position, 4, max_speed)`; no
  phase advance (DISENGAGE still runs).
- **Rails:** `on_suspended()` → light ARMED (the profile is already armed by `BaseEnemy.suspend_ai()`), `squad.leave`
  if any. `tick()` is never called again.
- **Squad (t8b only):** a drone with a squad behaves exactly like a solo LEAD; it calls `claim_side` / `release_side`
  / `release_lead` / `leave` at the points above and `update_target(target.position, heading)` each tick
  (heading = velocity dir, else `facing` below 20 px/s — computed in the brain, N15). Role-dependent behaviour is t8c.
  **Squad of one (review B2):** `SquadController.release_lead()` on a sole member leaves nobody eligible and pins the
  member to REAR (`squad_controller.gd` `_reassign(force_rear)`). Since `WaveManager` gives every loose spawn a board of
  one, that would turn every solo level drone into a REAR after its first attack once t8c makes REAR passive. So the
  brain calls `release_lead` only when `squad.members().size() >= 2`; a sole member stays LEAD. `SquadController` is
  not changed. Recorded in DECISIONS for t8c.
- **Interpretation (epic §4 "a burst toward a stationary player uses `facing`"):** with a stationary player the
  prediction degenerates to the player's position, so the burst goes straight at it and the drone's **facing**
  (rotation) at burst start is along the burst direction — the wind-up telegraph points where it will go. That is
  what the case asserts.
- **Lock timing:** the epic lists "lock lead / lock aim" among WINDUP's steps without saying when. It is re-evaluated
  every WINDUP tick (the drone visibly tracks) and locked on the last one, so `lead_time` is measured from the moment
  the burst starts, which is what `distance / burst_speed` means.

### Other edits

- Gate rosters: add `swarm_drone` to `ROSTER` in `test_enemy_contact_damage.gd` (with its config),
  `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`. (Config isolation and sprite transparency
  discover the directory by themselves; the single-writer gate sweeps `*_brain.gd` and mover-driven roots.)
- `test_engagement_deadline.gd`: replace `ENGAGE_SECONDS`/`EXIT_SPEED`/`ACCELERATION` constants with values read from
  `swarm_drone_config.tres`; add `swarm_drone.tscn` to its scene list (Kamikaze and Interceptor stay until t14/t9).
- `global/enemy_ai/engagement_budget.gd`: `remaining() -> float` (`INF` inactive, `max(seconds − elapsed, 0)`
  otherwise) + a case in `tests/unit/test_engagement_budget.gd`.
- `DECISIONS.md` (Phase 2 section): B5 braking 900; `max_turn_rate` 10 / `turn_lerp` 20; corkscrew 120 px/s at 0.6 Hz
  (≈ 32 px lateral swing; the epic's 60 px/s at 1.5 Hz swings ≈ 6 px, invisible on a 32 px hull — `amplitude` is a
  velocity, lateral displacement ≈ amplitude / (2π·f)); `phase_changed` signal; lock-on-last-WINDUP-tick; the WINDUP
  budget gate instead of N19's deferral; a sole squad member keeps LEAD; DISENGAGE leaves the squad and picks its edge
  once; the "uses facing" reading of epic §4.

## Build sequence

1. Config script + `.tres` + config unit test (both inequalities). 
2. Scene + `SwarmDrone` script + a brain stub; add to the three rosters; gates green.
3. Brain phases, driven by `tests/integration/test_swarm_drone.gd` written first (cases below).
4. Repoint `test_engagement_deadline.gd`.
5. `ENEMY.md`, DECISIONS, module docs (`updating-project-docs`).
6. `bash /agent/verify.sh` and `scripts/check-test-leaks.sh`.

## Test plan — `tests/integration/test_swarm_drone.gd`

Dual-mode cases use `use_parameters(["open_space", "assault"])` on a label and build the harness in the body; the
drone is driven by hand with the `_tick()` exact-integration helper, `set_physics_process(false)`, fixed `rng_seed`.
Assault cases place the player mid-corridor (640, 360) and the drone inside the visible rect unless stated.

**Drive rules (review N5, B5).** Hand-ticked cases: `set_physics_process(false)` and the exact-integration `_tick()`.
Seams on the brain, used only by tests: `enter_phase(p)` (the same entry code a real transition runs) and the public
fields above. The harness player is a `CharacterBody2D` whose `velocity` the test sets (the harness never integrates
it, so a non-zero velocity is a pure prediction input). Real-physics cases (`wait_physics_frames`) build the player
from `contact_fixture.build_player()` **and add it to group `player`**, so the brain perceives it; each case says
whether the drone moves.

| Case | Mode | Assertion |
|---|---|---|
| config: steady-state pin | — | `overshoot_turn_rate × max_speed ≤ acceleration` |
| config: braking-phase pin (B5) | — | `rate × (overshoot_seconds − (burst_speed − max_speed)/braking) ≥ deg_to_rad(60)` |
| **config flows through** (B1) | — | a drone whose private config (after `instantiate()`, before `add_child`) has **non-scene** values — `max_health` 55, `collision_damage` 41, `blast_radius` 70, `blast_damage` 9, `braking` 777, `second_passes` 2, `engage_seconds` 2.0 — reports exactly those on `Health`, `ContactHitBox.damage`, the profile, the mover and the brain |
| **budget from config** (B1) | assault | that drone (`engage_seconds` 2.0) is not in DISENGAGE on any tick before 2.0 s and is in DISENGAGE at 2.0 s + one tick |
| approach corkscrews | both | drone 700 px straight above the player: during APPROACH the max lateral offset from the drone→player line is > 15 px (a straight seek gives 0); reaches CLOSE_IN |
| corkscrew phase from rng | — | seeds A ≠ B → different corkscrew phases; same seed → equal (the control) |
| close-in settles on the ring | both | from 350 px, CLOSE_IN → WINDUP with the distance at WINDUP entry within 200 ± 30 and never below 150 during CLOSE_IN |
| **far target → lead 0.8** | both | player 600 px off, `velocity` (0, 150) (perpendicular to the line of sight); `enter_phase(WINDUP)`, tick `windup_seconds`: at BURST `lead_time == 0.8` and `aim == position + velocity·0.8` (≠ the 0.4 point by 60 px) |
| **near target → lead 0.4** | both | player 60 px off, same velocity: `lead_time == 0.4`, `aim == position + velocity·0.4` |
| mid prediction | both | player 288 px off: `lead_time ≈ 0.6` (± 0.01) and the aim matches |
| stationary player → burst along facing | both | drone enters WINDUP by itself from CLOSE_IN (tangential flight, ≈ 90° off the aim): burst velocity direction == dir to the player (± 0.01 rad); the drone's facing at burst start within 0.05 rad of it. Plus a 180° variant (facing set pointing away at WINDUP entry): within 0.05 rad |
| windup light & hold | both | CHARGING on every WINDUP tick; profile unarmed; speed ≤ 5 px/s by the end of WINDUP when entered at 220 px/s |
| burst light & armed | both | ARMED + `is_armed()` on every BURST tick; OFF and disarmed in OVERSHOOT |
| **overshoot curve** | open_space | drone at O, `enter_phase(BURST)` with `aim` locked at O + (200, 0), player parked out of the way; on OVERSHOOT entry the player is **teleported** to the drone + (0, 200) — exactly 90° off the velocity heading. Every OVERSHOOT tick: heading change ≤ `rate·dt + 1e-3` and its sign toward the player's bearing (or zero); speed ≥ 0.5 × `max_speed`; total turn at the end ≥ 60° |
| overshoot in corridor | assault | same setup mid-corridor: sequence BURST → OVERSHOOT → WINDUP and speed ≥ 0.5 × `max_speed` throughout OVERSHOOT |
| **exactly one second pass** | both | the player is teleported 600 px behind the drone at each BURST entry so every burst misses: sequence WINDUP, BURST, OVERSHOOT, WINDUP, BURST, OVERSHOOT, REJOIN; `burst_count == 2` at REJOIN |
| contact while armed | real physics | drone held still (physics off), `enter_phase(BURST)` on top of a real player hurtbox: `detonated` once, drone freed, `was_killed == true`; player health lower than before (30 contact + 15 blast, not asserted exactly) |
| **no damage in CLOSE_IN** | real physics | brain **running** (physics on), drone placed 150 px from a grouped real player so it is in CLOSE_IN, then moved onto the hurtbox each frame for 10 physics frames while its phase stays CLOSE_IN: player health unchanged, `is_armed()` false |
| **blast when shot within `blast_radius`** | real physics | drone held still, armed via `enter_phase(BURST)` 40 px from a real player hurtbox (contact 13 + player 12 = 25 < 40; blast 48 + 12 = 60 > 40), then `health.decrease(30)`: player loses exactly `blast_damage` 15; unarmed control (`enter_phase(CLOSE_IN)`): loses 0 |
| **Assault: never before `engage_seconds`** | assault | shipped config: no DISENGAGE before 5.5 s, DISENGAGE on the tick the budget expires, and speed ≤ `max_speed` + 1 at that tick (no burst straddles expiry) |
| **budget gate** | assault | a drone whose remaining budget is < 1.14 s when CLOSE_IN would end never enters WINDUP again before DISENGAGE |
| Assault: exit and free | assault | after DISENGAGE, not freed while inside `projectile_world_rect()`; freed once strictly outside; freed within 5.5 + 3.4 s of spawn from mid-corridor |
| open_space: never disengages | open_space | 12 s of ticking: never DISENGAGE, `remaining()` INF |
| Assault: below-screen spawn enters | assault | spawn at (640, 1300) — asserted **outside** the visible rect at tick 0 — inside the visible rect within 600 ticks |
| **corridor filters a burst toward an edge** | both, compared | the same drone/player setup near the bottom edge, run once per harness: the assault run's max excursion past the visible bottom edge is strictly below the open_space run's (which exceeds it) |
| **rail suspension arms** | real tree | an `EnemyPathMover` child added under a camera → `is_ai_suspended()`, `contact_profile.is_armed()`, light ARMED |
| squad calls | open_space | squad of one: joined as LEAD; during WINDUP `claim_side` latched (a second probe member's claim for the same side gets a different one); released in OVERSHOOT; after REJOIN still LEAD (B2). Squad of two: after REJOIN the drone is no longer LEAD |

Also `tests/unit/test_engagement_budget.gd`: `remaining()` is INF inactive, counts down, floors at 0.


Plus: the deadline test reads the config; every gate listed in the AC stays green.

## Risks

- **Overshoot turn below 60° in practice.** Mitigated by the braking-phase pin and the replay; if the replayed test
  still misses, raise `braking` further (1200) rather than weaken the assertion.
- **`move_and_slide` drift in hand-ticked tests** — use the exact-integration `_tick()` from `test_enemy_dual_mode.gd`.
- **Real-physics cases leaking** — `wait_physics_frames` only, no timers; run `scripts/check-test-leaks.sh`.
- **Assault harness camera** — `ArenaCamera` must be in the tree before the drone so the mover's AUTO constraint and
  the budget resolve it; the harness already orders it so.

## Out of scope

Squad roles, FORM, flank pincer, formation recovery (t8c); hub idle (t8d); sprite (t12); any level spawn (t14–t16);
Kamikaze removal (t14).

## Response to review round 1

| Finding | Change |
|---|---|
| B1 config reaches the brain after its `_ready` | Budget and `passes_left` built on the first tick; "config flows through" and "budget from config" cases use non-scene values |
| B2 `release_lead` on a squad of one → REAR | Brain skips `release_lead` for a sole member; tested both ways (one / two members); DECISIONS entry for t8c |
| B3 deferral breaks the deadline | No deferral: WINDUP is gated on `budget.remaining() ≥ 1.14 s`, so expiry never lands in a burst and the §2.6 formula stays a true bound; `EngagementBudget.remaining()` added |
| B4 facing tolerance | `turn_lerp` 20, `max_turn_rate` 10 rad/s; the case states its entry geometry and adds a 180° variant |
| B5 three cases cannot fail | Spawn at y 1300 asserted outside at tick 0; edge case compares assault vs open_space excursion; prediction cases give the player a perpendicular velocity so the aim point pins the clamp; seam named (`enter_phase`) |
| N1 hold drift | Hold at the stopping point; numeric threshold (≤ 5 px/s) |
| N2 CLOSE_IN geometry | `radius_rate` 0; tangential 130 px/s; a settle case |
| N3 corkscrew | 120 px/s at 0.6 Hz (≈ 32 px swing), DECISIONS entry; case threshold 15 px |
| N4 crop | `Rect2(0,0,42,42)`; nose checked by eye |
| N5 real-physics drive | Stated per case; player added to group `player`; contact case not exact |
| N6 overshoot setup | Player teleported to 90° off at OVERSHOOT entry |
| N7 / N8 | Both recorded in DECISIONS |
